require 'spec_helper'

module Bosh::Director
  describe LogsFetcher do
    subject { described_class.new(instance_manager, log_bundles_cleaner, log) }

    let(:instance_manager) { instance_double(Bosh::Director::Api::InstanceManager) }
    let(:log_bundles_cleaner) { instance_double(Bosh::Director::LogBundlesCleaner) }
    let(:mock_instance_model) do
      instance_double(Bosh::Director::Models::Instance,
                      job: 'some-job',
                      uuid: 'some-uuid',
                      index: 'some-index')
    end
    let(:filters) do
      filters = double 'filters'
      allow(filters).to receive(:to_s).and_return 'some-filters'
      filters
    end
    let(:log) { double('logger') }
    let(:blobstore) { instance_double(Bosh::Director::Blobstore::Client) }

    before do
      allow(App).to receive_message_chain(:instance, :blobstores, :blobstore).and_return(blobstore)
      allow(blobstore).to receive(:can_sign_urls?).and_return(false)
      allow(mock_instance_model).to receive_message_chain(:active_vm, :stemcell_api_version)
    end

    describe '#fetch' do
      let(:mock_agent) do
        instance_double(Bosh::Director::AgentClient)
      end

      context 'after successfully logging and cleaning bundles' do
        before do
          expect(log).to receive(:info).with(match(/some-log-type.*some-filters/))
          expect(log_bundles_cleaner).to receive(:clean)
          expect(instance_manager)
            .to receive(:agent_client_for)
            .with(mock_instance_model)
            .and_return mock_agent
        end

        context 'when the agent finds logs for that type and filters' do
          let(:packaged_logs_blob_id) { '11111111-1111-4111-8111-111111111111' }

          it 'returns the blobstore ID' do
            expect(mock_agent).to receive(:fetch_logs).and_return(
              'blobstore_id' => packaged_logs_blob_id,
            )

            blob, sha = subject.fetch(mock_instance_model, 'some-log-type', filters)
            expect(blob).to eq packaged_logs_blob_id
            expect(sha).to be_nil
          end

          it 'returns the sha as well if the agent provides one' do
            expect(mock_agent).to receive(:fetch_logs).and_return(
              'blobstore_id' => packaged_logs_blob_id,
              'sha1' => 'sha1-digest',
            )

            blob, sha = subject.fetch(mock_instance_model, 'some-log-type', filters)
            expect(blob).to eq packaged_logs_blob_id
            expect(sha).to eq 'sha1-digest'
          end

          it 'registers the blob with the cleaner when marked persistent' do
            expect(mock_agent).to receive(:fetch_logs).and_return(
              'blobstore_id' => packaged_logs_blob_id,
            )

            expect(log_bundles_cleaner).to receive(:register_blobstore_id).with(packaged_logs_blob_id)

            subject.fetch(mock_instance_model, 'some-log-type', filters, true)
          end
        end

        context 'when signed urls are available' do
          let(:signed_url) { 'https://signed-url.com' }
          let(:blobstore_id) { '22222222-2222-4222-8222-222222222222' }

          before do
            allow(blobstore).to receive(:generate_object_id).and_return(blobstore_id)
            allow(blobstore).to receive(:headers).and_return({})
            allow(blobstore).to receive(:sign).with(blobstore_id, 'put').and_return(signed_url)
          end

          context 'and are enabled' do
            before do
              allow(blobstore).to receive(:can_sign_urls?).and_return(true)
            end

            it 'generates a blobstore id, signs the url and fetches logs with the signed url' do
              expect(mock_agent).to receive(:fetch_logs_with_signed_url)
                .with({ signed_url:, log_type: 'some-log-type', filters: })
                .and_return('sha1' => 'sha1-digest')
              blob, sha = subject.fetch(mock_instance_model, 'some-log-type', filters)
              expect(blob).to eq blobstore_id
              expect(sha).to eq 'sha1-digest'
            end

            it 'raises signing errors' do
              allow(blobstore).to receive(:sign).with(blobstore_id, 'put').and_raise('oops')
              expect do
                subject.fetch(mock_instance_model, 'some-log-type', filters)
              end.to raise_error(RuntimeError, 'oops')
            end

            it 'raises fetch errors' do
              expect(mock_agent).to receive(:fetch_logs_with_signed_url)
                .with({ signed_url:, log_type: 'some-log-type', filters: })
                .and_raise('oops')
              expect do
                subject.fetch(mock_instance_model, 'some-log-type', filters)
              end.to raise_error(RuntimeError, 'oops')
            end

            context 'and encryption is enabled' do
              let(:encryption_headers) { { 'x-encrypt-header-key' => :value } }

              before do
                allow(blobstore).to receive(:headers).and_return(encryption_headers)
              end

              it 'adds headers to the request' do
                expect(mock_agent).to receive(:fetch_logs_with_signed_url)
                  .with({ signed_url:, log_type: 'some-log-type', filters:,
                          blobstore_headers: encryption_headers })
                  .and_return('sha1' => 'sha1-digest')
                blob, sha = subject.fetch(mock_instance_model, 'some-log-type', filters)
                expect(blob).to eq blobstore_id
                expect(sha).to eq 'sha1-digest'
              end
            end
          end

          context 'and are not enabled' do
            before do
              allow(blobstore).to receive(:can_sign_urls?).and_return(false)
            end

            it 'falls back to fetching logs without signed url' do
              expect(mock_agent).to receive(:fetch_logs).and_return(
                'blobstore_id' => '11111111-1111-4111-8111-111111111111',
              )

              blob, sha = subject.fetch(mock_instance_model, 'some-log-type', filters)
              expect(blob).to eq '11111111-1111-4111-8111-111111111111'
              expect(sha).to be_nil
            end
          end
        end

        context 'when the agent returns a non-UUID blobstore id without signed urls' do
          it 'raises AgentTaskInvalidBlobstoreId' do
            expect(mock_agent).to receive(:fetch_logs).and_return(
              'blobstore_id' => 'not-a-uuid',
            )

            expect do
              subject.fetch(mock_instance_model, 'some-log-type', filters)
            end.to raise_error(AgentTaskInvalidBlobstoreId, /valid blobstore object id/)
          end
        end

        context 'when the agent does not find the logs' do
          it 'raises an error' do
            expect(mock_agent).to receive(:fetch_logs).and_return(
              'blobstore_id' => nil,
            )

            expect do
              subject.fetch(mock_instance_model, 'some-log-type', filters)
            end.to raise_error AgentTaskNoBlobstoreId
          end
        end
      end
    end
  end
end
