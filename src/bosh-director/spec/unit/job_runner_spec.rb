require 'spec_helper'

module Bosh::Director
  describe JobRunner do
    let(:sample_job_class) do
      Class.new(Jobs::BaseJob) do
        define_method :perform do
          'foo'
        end
      end
    end

    let(:task) { FactoryBot.create(:models_task, id: 42) }

    let(:tasks_dir) { Dir.mktmpdir }
    let(:task_dir) { File.join(tasks_dir, 'tasks', task.id.to_s) }

    let(:worker_name) {'workername1'}
    before do
      FileUtils.mkdir_p(task_dir)

      allow(Config).to receive(:base_dir).and_return(tasks_dir)
      allow(Config).to receive(:task_checkpoint_interval).and_return(30)
      allow(Config).to receive(:cloud_options).and_return({})
      allow(Config).to receive(:runtime).and_return('instance' => 'name/id', 'ip' => '127.0.127.0')
    end

    it "doesn't accept job class that is not a subclass of base job" do
      expect { JobRunner.new(Class.new, 42, worker_name) }.to raise_error(DirectorError, /invalid director job/i)
    end

    it 'performs the requested job with provided args' do
      runner = JobRunner.new(sample_job_class, 42, worker_name)
      allow(runner).to receive(:run_checkpointing)

      runner.run
      task.reload
      expect(runner).to have_received(:run_checkpointing)
      expect(task.state).to eq('done')
      expect(task.result).to eq('foo')
    end

    it 'whines when no task is found' do
      expect { JobRunner.new(sample_job_class, 155, worker_name) }.to raise_error(TaskNotFound)
    end

    context 'when task directory is missing' do
      let(:task) { FactoryBot.create(:models_task, id: 188) }

      it 'creates task directory if it is missing' do
        task.save
        JobRunner.new(sample_job_class, 188, worker_name)
        expect(File).to exist(task_dir)
      end
    end

    it 'sets up task logs: debug, event, result' do
      event_log = double('event log')
      task_result = double('result file')

      task_writer = TaskDBWriter.new(:event_output, task.id)
      allow(TaskDBWriter).to receive(:new)
        .with(:event_output, task.id).and_return(task_writer)

      allow(EventLog::Log)
        .to receive(:new)
        .with(task_writer)
        .and_return(event_log)

      allow(TaskDBWriter).to receive(:new)
        .with(:result_output, task.id)
        .and_return(task_result)

      JobRunner.new(sample_job_class, 42, worker_name)

      logger_repo = Logging::Repository.instance

      config = Config
      expect(config.event_log).to eq(event_log)
      expect(config.logger).to eq(logger_repo.fetch('DirectorJobRunner'))
      expect(config.result).to eq(task_result)
    end

    it 'logs the worker name and process information' do
      runner = JobRunner.new(sample_job_class, 42, worker_name)
      allow(runner).to receive(:run_checkpointing)

      logger = Logging::Repository.instance.fetch('DirectorJobRunner')
      allow(logger).to receive(:info)
      expect(logger).to receive(:info).with("Running from worker 'workername1' on name/id (127.0.127.0)")
      runner.run
    end

    it 'should not log standard blacklist messages' do
      JobRunner.new(sample_job_class, 42, worker_name)

      Config.logger.debug('before')
      Config.logger.debug('(10.01s) (conn: 123123123) SELECT NULL')
      Config.logger.debug('after')

      log_contents = File.read(task_dir + '/debug')

      expect(log_contents).to include('before')
      expect(log_contents).to include('after')
      expect(log_contents).not_to include('SELECT NULL')
    end

    it 'should generate timestamp with milliseconds' do
      Timecop.freeze do
        JobRunner.new(sample_job_class, 42, worker_name)
        Config.logger.debug('test')

        time = Time.new
        time_format = time.strftime('%Y-%m-%dT%H:%M:%S.') << format('%06d ', time.usec)
        log_contents = File.read(task_dir + '/debug')
        expect(log_contents).to match(/D, \[#{time_format}.*\] \[\] DEBUG -- DirectorJobRunner: test/)
      end
    end

    it 'handles task cancellation' do
      job = Class.new(Jobs::BaseJob) do
        define_method(:perform) do |*_args|
          raise TaskCancelled, 'task cancelled'
        end
      end

      runner = JobRunner.new(job, 42, worker_name)
      allow(runner).to receive(:run_checkpointing)

      runner.run
      task.reload
      expect(task.state).to eq('cancelled')
    end

    it 'handles task error' do
      job = Class.new(Jobs::BaseJob) do
        define_method(:perform) { |*_args| raise 'Oops' }
      end

      runner = JobRunner.new(job, 42, worker_name)
      allow(runner).to receive(:run_checkpointing)

      runner.run
      task.reload
      expect(task.state).to eq('error')
      expect(task.result).to eq('Oops')
    end
  end

  describe TaskCheckPointer do
    before { FactoryBot.create(:models_task, id: 42) }

    it 'updates task checkpoint time' do
      task = Models::Task[42]
      expect(task.checkpoint_time).to be(nil)
      TaskCheckPointer.new(task.id).checkpoint

      task.reload
      expect(task.checkpoint_time).to_not be(nil)
    end
  end
end
