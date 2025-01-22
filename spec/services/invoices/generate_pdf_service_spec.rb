# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::GeneratePdfService, type: :service do
  subject(:invoice_generate_service) { described_class.new(invoice:, context:) }

  let(:context) { 'graphql' }
  let(:organization) { create(:organization, name: 'LAGO') }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:invoice) { create(:invoice, customer:, status: :finalized, organization:) }
  let(:credit) { create(:credit, invoice:) }
  let(:fees) { create_list(:fee, 3, invoice:) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice:, subscription:) }
  let(:pdf_content) do
    File.read(Rails.root.join('spec/fixtures/blank.pdf'))
  end

  let(:pdf_generator) { instance_double(Utils::PdfGenerator) }
  let(:pdf_response) do
    BaseService::Result.new.tap { |r| r.io = StringIO.new(pdf_content) }
  end

  before do
    invoice_subscription

    allow(Utils::PdfGenerator).to receive(:new)
      .and_return(pdf_generator)
    allow(pdf_generator).to receive(:call)
      .and_return(pdf_response)
  end

  describe '#call' do
    it 'generates the invoice synchronously' do
      result = invoice_generate_service.call

      expect(result.invoice.file).to be_present
    end

    it 'calls the SendWebhook job' do
      expect { invoice_generate_service.call }.to have_enqueued_job(SendWebhookJob)
    end

    context 'with not found invoice' do
      let(:invoice_subscription) { nil }
      let(:invoice) { nil }

      it 'returns a result with error' do
        result = invoice_generate_service.call

        expect(result.success).to be_falsey
        expect(result.error.error_code).to eq('invoice_not_found')
      end
    end

    context 'when invoice is draft' do
      let(:invoice) { create(:invoice, customer:, status: :draft, organization:) }

      it 'returns a result with error' do
        result = invoice_generate_service.call

        expect(result.success).to be_falsey
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq('is_draft')
      end
    end

    context 'with already generated file' do
      before do
        invoice.file.attach(
          io: StringIO.new(File.read(Rails.root.join('spec/fixtures/blank.pdf'))),
          filename: 'invoice.pdf',
          content_type: 'application/pdf'
        )
      end

      it 'does not generate the pdf' do
        allow(LagoHttpClient::Client).to receive(:new)

        invoice_generate_service.call

        expect(LagoHttpClient::Client).not_to have_received(:new)
      end
    end

    context 'when a billable metric is deleted' do
      let(:billable_metric) { create(:billable_metric, :deleted) }
      let(:fees) { [create(:charge_fee, subscription:, invoice:, charge_filter:, charge:, amount_cents: 10)] }
      let(:charge) { create(:standard_charge, :deleted, billable_metric:) }
      let(:billable_metric_filter) { create(:billable_metric_filter, :deleted, billable_metric:) }
      let(:charge_filter) do
        create(:charge_filter, :deleted, charge_id: charge.id, properties: {amount: '10'})
      end
      let(:charge_filter_value) do
        create(
          :charge_filter_value,
          :deleted,
          charge_filter:,
          billable_metric_filter:,
          values: [billable_metric_filter.values.first]
        )
      end

      before do
        charge_filter_value
      end

      it 'generates the invoice synchronously' do
        result = invoice_generate_service.call

        expect(result.invoice.file).to be_present
      end
    end

    context "when invoice is self billed" do
      let(:invoice) do
        create(:invoice, :self_billed, customer:, status: :finalized, organization:)
      end

      let(:pdf_generator) { instance_double(Utils::PdfGenerator, call: pdf_response) }

      let(:pdf_response) do
        BaseService::Result.new.tap { |r| r.io = StringIO.new(pdf_content) }
      end

      let(:pdf_content) { File.read(Rails.root.join('spec/fixtures/blank.pdf')) }

      before do
        allow(Utils::PdfGenerator).to receive(:new).and_return(pdf_generator)
      end

      it "calls the self billed template" do
        invoice_generate_service.call

        expect(Utils::PdfGenerator).to have_received(:new).with(template: 'invoices/v4/self_billed', context: invoice)
      end
    end

    context 'when in API context' do
      let(:context) { 'api' }

      it 'calls the SendWebhook job' do
        expect { invoice_generate_service.call }.to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when in Admin context' do
      let(:context) { 'admin' }

      before do
        invoice.file.attach(
          io: StringIO.new(File.read(Rails.root.join('spec/fixtures/blank.pdf'))),
          filename: 'invoice.pdf',
          content_type: 'application/pdf'
        )
      end

      it 'generates the invoice synchronously' do
        result = invoice_generate_service.call

        expect(result.invoice.file.filename.to_s).not_to eq('invoice.pdf')
      end
    end
  end
end
