require 'shellwords'

module SharedSupport
  class Postgresql < DBHelper
    TYPE = 'postgresql'
    DEFAULTS = {
      adapter: 'postgresql',
      username: 'postgres',
      password: '',
      host: '127.0.0.1',
      port: 5432,
    }

    def initialize(db_options:)
      super(db_options: DEFAULTS.merge(db_options))
    end

    def connection_string(this_db_name = @db_name)
      "postgres://#{@username}:#{@password}@#{@host}:#{@port}/#{this_db_name}"
    end

    # Assumes: login via psql w/o password
    def create_db
      execute_sql(%(CREATE DATABASE "#{db_name}";), connection_string('postgres'))
    end

    def kill_connections
      execute_sql(
        %(
          SELECT pg_terminate_backend(pg_stat_activity.pid)
          FROM pg_stat_activity
          WHERE pg_stat_activity.datname = '#{db_name}' AND pid <> pg_backend_pid();
        ),
      )
    end

    def drop_db
      kill_connections
      sql = %(
        REVOKE CONNECT ON DATABASE "#{db_name}" FROM public;
        DROP DATABASE "#{db_name}";
      )
      execute_sql(sql, connection_string('postgres'))
    end

    def current_tasks
      tasks_list_cmd = %{
        SELECT description, output
        FROM tasks
        WHERE state='processing';
      }
      task_lines = sql_results_for(tasks_list_cmd)

      result = []
      task_lines.each do |task_line|
        items = task_line.split('|').map(&:strip)
        result << { description: items[0], output: items[1] }
      end

      result
    end

    def current_locked_jobs
      jobs_cmd = %{
        SELECT *
        FROM delayed_jobs
        WHERE locked_by IS NOT NULL;
      }
      sql_results_for(jobs_cmd)
    end

    def truncate_db
      cmds = drop_constraints_cmds + clear_table_cmds + add_constraints_cmds
      execute_sql(cmds.join(';'))
    end

    private

    def execute_sql(sql, this_connection_string = connection_string)
      run_command(%{#{sql_cmd(sql, this_connection_string)} > /dev/null})
    end

    def sql_results_for(sql, this_connection_string = connection_string)
      %x{#{sql_cmd(sql, this_connection_string)}}.lines.to_a[2...-2] || []
    end

    def sql_cmd(sql, this_connection_string = connection_string)
      %{echo #{Shellwords.escape(sql)} | psql #{this_connection_string}}
    end

    def drop_constraints_cmds
      drop_constraints_cmds_cmd = %{
        SELECT
          CONCAT('ALTER TABLE ',nspname,'.',relname,' DROP CONSTRAINT ',conname,';')
        FROM pg_constraint
          INNER JOIN pg_class ON conrelid=pg_class.oid
          INNER JOIN pg_namespace ON pg_namespace.oid=pg_class.relnamespace
        WHERE nspname != 'pg_catalog'
        ORDER BY CASE WHEN contype='f' THEN 0 ELSE 1 END,contype,nspname,relname,conname
      }
      sql_results_for(drop_constraints_cmds_cmd)
    end

    def clear_table_cmds
      clear_table_cmds_cmd = %{
        SELECT
          CONCAT('DELETE FROM \"', tablename, '\"')
        FROM pg_tables
        WHERE
          schemaname = 'public' AND
          tablename <> 'schema_migrations'
        UNION
        SELECT
          CONCAT('alter sequence ', relname, ' restart with 1')
        FROM pg_class
        WHERE
          relkind = 'S'
      }
      sql_results_for(clear_table_cmds_cmd)
    end

    def add_constraints_cmds
      add_constraints_cmds_cmd = %{
        SELECT
          'ALTER TABLE '||nspname||'.'||relname||' ADD CONSTRAINT '||conname||' '|| pg_get_constraintdef(pg_constraint.oid)||';'
        FROM pg_constraint
          INNER JOIN pg_class ON conrelid=pg_class.oid
          INNER JOIN pg_namespace ON pg_namespace.oid=pg_class.relnamespace
        WHERE nspname != 'pg_catalog'
        ORDER BY CASE WHEN contype='f' THEN 0 ELSE 1 END DESC,contype DESC,nspname DESC,relname DESC,conname DESC;
      }
      sql_results_for(add_constraints_cmds_cmd)
    end
  end
end
