#!/usr/bin/env ruby
#
# MySQL Disk Usage Metrics
# ===

require 'sensu-plugin/metric/cli'
require 'mysql'
require 'inifile'

class CheckMysqlDisk < Sensu::Plugin::Metric::CLI::Graphite
  option :host,
         short: '-h',
         long: '--host=VALUE',
         description: 'Database host'

  option :user,
         short: '-u',
         long: '--username=VALUE',
         description: 'Database username'

  option :pass,
         short: '-p',
         long: '--password=VALUE',
         description: 'Database password'

  option :ini,
         description: 'My.cnf ini file',
         short: '-i',
         long: '--ini VALUE'

  option :scheme,
         description: 'Metric naming scheme, text to prepend to metric',
         short: '-s SCHEME',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostname}.mysql"

  def run
    if config[:ini]
      ini = IniFile.load(config[:ini])
      section = ini['client']
      db_user = section['user']
      db_pass = section['password']
    else
      db_user = config[:user]
      db_pass = config[:pass]
    end
    db_host = config[:host]
    mysql_shorthostname = db_host.split('.')[0]

    if [db_host, db_user, db_pass].any?(&:nil?)
      unknown 'Must specify host, user and password'
    end

    begin
      db = Mysql.new(db_host, db_user, db_pass)

      results = db.query <<-EOSQL
        select table_schema,
        count(*) as tables,
        sum(table_rows) as rows,
        sum(data_length) as data,
        sum(index_length) as idx,
        sum(data_length + index_length) as total_size
        from information_schema.tables
        where table_schema not in ("information_schema", "mysql", "performance_schema", "sys")
        group by table_schema
      EOSQL

      unless results.nil?
        results.each_hash do |row|
          output "#{config[:scheme]}.#{mysql_shorthostname}.disk.#{row['table_schema']}.tables", row['tables']
          output "#{config[:scheme]}.#{mysql_shorthostname}.disk.#{row['table_schema']}.rows", row['rows']
          output "#{config[:scheme]}.#{mysql_shorthostname}.disk.#{row['table_schema']}.data", row['data']
          output "#{config[:scheme]}.#{mysql_shorthostname}.disk.#{row['table_schema']}.idx", row['idx']
          output "#{config[:scheme]}.#{mysql_shorthostname}.disk.#{row['table_schema']}.total_size", row['total_size']
        end
      end
    ensure
      db.close if db
    end

    ok
  end
end
