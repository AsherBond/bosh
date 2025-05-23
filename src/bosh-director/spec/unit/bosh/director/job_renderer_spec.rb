require 'spec_helper'

module Bosh::Director
  describe JobRenderer do
    let(:instance_group) do
      FactoryBot.build(:deployment_plan_instance_group,
        name: 'test-instance-group',
      )
    end
    let(:blobstore_client) { instance_double(Bosh::Director::Blobstore::Client) }
    let(:blobstore_files) { [] }
    let(:cache) { Bosh::Director::Core::Templates::TemplateBlobCache.new }
    let(:encoder) { DnsEncoder.new }

    let(:variables_interpolator) { instance_double(Bosh::Director::ConfigServer::VariablesInterpolator) }

    let(:instance_plan) do
      DeploymentPlan::InstancePlan.new(existing_instance: instance_model, desired_instance: DeploymentPlan::DesiredInstance.new(instance_group), instance: instance, variables_interpolator: variables_interpolator)
    end

    let(:instance) do
      deployment = instance_double(DeploymentPlan::Planner, model: deployment_model)
      availability_zone = DeploymentPlan::AvailabilityZone.new('z1', {})
      DeploymentPlan::Instance.create_from_instance_group(instance_group, 5, 'started', deployment, {}, availability_zone, per_spec_logger, variables_interpolator)
    end

    let(:deployment_model) { FactoryBot.create(:models_deployment, name: 'fake-deployment') }
    let(:instance_model) { FactoryBot.create(:models_instance, deployment: deployment_model) }
    let(:link_provider_intents) { [] }

    before do
      job_tgz_path = asset_path('dummy_job_with_single_template.tgz')
      allow(blobstore_client).to receive(:get) { |_, f| blobstore_files << f.path; f.write(File.read(job_tgz_path)) }
      allow(Bosh::Director::App).to receive_message_chain(:instance, :blobstores, :blobstore).and_return(blobstore_client)
    end

    describe '#render_job_instances_with_cache' do
      before do
        release_version = DeploymentPlan::ReleaseVersion.parse(deployment_model, 'name' => 'fake-release', 'version' => '123')

        job1 = DeploymentPlan::Job.new(release_version, 'dummy')
        job1.bind_existing_model(FactoryBot.create(:models_template,
          name: 'dummy',
          spec_json: '{ "templates": { "ctl.erb": "bin/dummy_ctl" } }',
          blobstore_id: 'my-blobstore-id',
          sha1: '16baf0c24e2dac2a21ccdcd4655be403a602f573'
        ))

        job2 = DeploymentPlan::Job.new(release_version, 'dummy')
        job2.bind_existing_model(FactoryBot.create(:models_template,
          name: 'dummy',
          spec_json: '{ "templates": { "ctl.erb": "bin/dummy_ctl" } }',
          blobstore_id: 'my-blobstore-id')
        )

        allow(instance_plan).to receive_message_chain(:spec, :as_template_spec).and_return('template' => 'spec')
        allow(instance_plan).to receive(:templates).and_return([job1, job2])
      end

      context 'when instance plan does not have templates' do
        before do
          allow(instance_plan).to receive(:templates).and_return([])
        end

        it 'does not render' do
          expect(per_spec_logger).to receive(:debug).with("Skipping rendering templates for 'test-instance-group/5': no job")
          expect {
            JobRenderer.render_job_instances_with_cache(per_spec_logger, [instance_plan], cache, encoder, link_provider_intents)
          }.not_to(change { instance_plan.rendered_templates })
        end
      end

      context 'when instance plan has templates' do
        it 'renders all templates for all instances of a instance_group' do
          expect(instance_plan.rendered_templates).to be_nil
          expect(instance.configuration_hash).to be_nil
          expect(instance.template_hashes).to be_nil

          JobRenderer.render_job_instances_with_cache(per_spec_logger, [instance_plan], cache, encoder, link_provider_intents)

          expect(instance_plan.rendered_templates.template_hashes.keys).to eq ['dummy']
          expect(instance.configuration_hash).to eq('d4712f01af58824081e9d964522782da9889cd1b')
          expect(instance.template_hashes.keys).to eq(['dummy'])
        end

        context 'when a template has already been downloaded' do
          it 'should reuse the downloaded template' do
            JobRenderer.render_job_instances_with_cache(per_spec_logger, [instance_plan], cache, encoder, link_provider_intents)

            expect(blobstore_client).to have_received(:get).once
          end
        end
      end

      context 'when getting the templates spec of an instance plan errors' do
        before do
          allow(instance).to receive(:instance_group_name).and_return('my_instance_group')
          allow(instance_plan).to receive_message_chain(:spec, :as_template_spec).and_raise StandardError, <<~ERRORMSG
            - Failed to find variable '/TestDirector/simple/i_am_not_here_1' from config server: HTTP code '404'
            - Failed to find variable '/TestDirector/simple/i_am_not_here_2' from config server: HTTP code '404'
            - Failed to find variable '/TestDirector/simple/i_am_not_here_3' from config server: HTTP code '404'
          ERRORMSG
        end

        it 'formats the error messages' do
          expected = <<~EXPECTED.strip
            - Unable to render jobs for instance group 'my_instance_group'. Errors are:
              - Failed to find variable '/TestDirector/simple/i_am_not_here_1' from config server: HTTP code '404'
              - Failed to find variable '/TestDirector/simple/i_am_not_here_2' from config server: HTTP code '404'
              - Failed to find variable '/TestDirector/simple/i_am_not_here_3' from config server: HTTP code '404'
          EXPECTED

          expect {
            JobRenderer.render_job_instances_with_cache(per_spec_logger, [instance_plan], cache, encoder, link_provider_intents)
          }.to(raise_error { |error| expect(error.message).to eq(expected) })
        end
      end
    end
  end
end
