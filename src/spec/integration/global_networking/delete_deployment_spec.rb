require 'spec_helper'

describe 'deleting deployment', type: :integration do
  with_reset_sandbox_before_each

  it 'should clean environment properly and free up resources', no_create_swap_delete: true do
    run_test create_swap_delete_enabled: false
  end

  it 'should clean environment properly and free up resources', create_swap_delete: true do
    run_test create_swap_delete_enabled: true
  end

  it 'should clean environment properly and free up resources even after a failed deployment' do
    current_sandbox.cpi.commands.make_create_vm_always_fail

    expect(current_sandbox.cpi.all_stemcells).to eq []
    expect(current_sandbox.cpi.vm_cids.count).to eq 0
    expect(current_sandbox.cpi.disk_cids.count).to eq 0
    expect(current_sandbox.cpi.all_ips.count).to eq 0
    expect(current_sandbox.cpi.all_snapshots.count).to eq 0

    expect(bosh_runner.run('deployments', failure_expected: true)).to match(/0 deployments/)

    manifest_hash = SharedSupport::DeploymentManifestHelper.simple_manifest_with_instance_groups
    manifest_hash['instance_groups'].first['instances'] = 1

    cloud_config_hash = SharedSupport::DeploymentManifestHelper.simple_cloud_config
    cloud_config_hash['disk_types'] = [{ 'name' => 'disk_a', 'disk_size' => 123 }]
    manifest_hash['instance_groups'].first['persistent_disk_type'] = 'disk_a'

    deploy_from_scratch(manifest_hash: manifest_hash, cloud_config_hash: cloud_config_hash, failure_expected: true)

    expect(bosh_runner.run('deployments')).to include('1 deployments')
    expect(bosh_runner.run('vms', deployment_name: 'simple')).to include('0 vms')
    output = scrub_random_ids(table(bosh_runner.run('instances', deployment_name: 'simple', json: true)))
    expect(output).to contain_exactly(
      'instance' => 'foobar/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
      'process_state' => '',
      'az' => '',
      'ips' => '',
      'deployment' => 'simple',
    )
    expect(bosh_runner.run('releases')).to include('1 releases')

    expect(current_sandbox.cpi.all_stemcells.count).to eq 1
    expect(current_sandbox.cpi.vm_cids.count).to eq 0
    expect(current_sandbox.cpi.disk_cids.count).to eq 0
    expect(current_sandbox.cpi.all_ips.count).to eq 0

    # Delete Deployment
    deployment_deletion_output = bosh_runner.run('delete-deployment', deployment_name: 'simple', json: true)
    expect(deployment_deletion_output).to match(/Deleting instances: foobar/)
    expect(deployment_deletion_output).to include('Succeeded')

    # Stemcells and releases remain after deletion of deployment
    expect(current_sandbox.cpi.all_stemcells.count).to eq 1
    expect(bosh_runner.run('releases')).to include('1 releases')

    expect(current_sandbox.cpi.vm_cids.count).to eq 0
    expect(current_sandbox.cpi.disk_cids.count).to eq 0
    expect(current_sandbox.cpi.all_ips.count).to eq 0
    expect(current_sandbox.cpi.all_snapshots.count).to eq 0

    expect(bosh_runner.run('deployments', failure_expected: true)).to include('0 deployments')
  end

  def run_test(create_swap_delete_enabled: false)
    assert_sandbox_contains_elements(0)

    expect(bosh_runner.run('deployments', failure_expected: true)).to match(/0 deployments/)

    manifest_hash = SharedSupport::DeploymentManifestHelper.simple_manifest_with_instance_groups
    manifest_hash['instance_groups'].first['instances'] = 1

    cloud_config_hash = SharedSupport::DeploymentManifestHelper.simple_cloud_config
    cloud_config_hash['disk_types'] = [{ 'name' => 'disk_a', 'disk_size' => 123 }]
    manifest_hash['instance_groups'].first['persistent_disk_type'] = 'disk_a'

    deploy_from_scratch(manifest_hash: manifest_hash, cloud_config_hash: cloud_config_hash)
    expect(bosh_runner.run('take-snapshot foobar/0', deployment_name: 'simple')).to include('Succeeded')

    expect(bosh_runner.run('deployments')).to include('1 deployments')
    expect(bosh_runner.run('vms', deployment_name: 'simple')).to include('1 vms')
    expect(bosh_runner.run('instances', deployment_name: 'simple')).to include('1 instances')
    expect(bosh_runner.run('releases', deployment_name: 'simple')).to include('1 releases')

    assert_sandbox_contains_elements(1)

    # Delete Deployment
    deployment_deletion_output = bosh_runner.run('delete-deployment', deployment_name: 'simple', json: true)
    expect(deployment_deletion_output).to match(/Deleting instances: foobar/)
    expect(deployment_deletion_output).to include('Succeeded')

    # Stemcells and releases remain after deletion of deployment
    expect(current_sandbox.cpi.all_stemcells.count).to eq 1
    expect(bosh_runner.run('releases')).to include('1 releases')

    expected_vms = create_swap_delete_enabled ? 1 : 0

    # We expect an orphaned VM
    expect(current_sandbox.cpi.vm_cids.count).to eq expected_vms
    expect(current_sandbox.cpi.disk_cids.count).to eq 1
    # We expect an orphaned VM
    expect(current_sandbox.cpi.all_ips.count).to eq expected_vms
    expect(current_sandbox.cpi.all_snapshots.count).to eq 1

    expect(bosh_runner.run('deployments', failure_expected: true)).to match(/0 deployments/)
  end

  def assert_sandbox_contains_elements(n)
    expect(current_sandbox.cpi.all_stemcells.count).to eq n
    expect(current_sandbox.cpi.vm_cids.count).to eq n
    expect(current_sandbox.cpi.disk_cids.count).to eq n
    expect(current_sandbox.cpi.all_ips.count).to eq n
    expect(current_sandbox.cpi.all_snapshots.count).to eq n
  end
end
