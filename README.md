# AWS RDS Aurora input plugin for [Fluentd](http://fluentd.org)

## Overview
This fluent input plugin collects RDS Aurora slowquery log with ParameterGroup option `log_output=FILE`.
This plugin fetches only the difference between the latest and previous fetched slow query log.

## Background
There are a lot of RDS mysql slowlog input plugins that collect mysql slowquery logs with ParameterGroup option `log_output=TABLE`.
However if you use RDS Aurora with the option, there are two following problems:

### 1. mysql.slow_log table is operated with Engine=CSV

mysql.slow_log table is operated with Engine=CSV and we cannot add index to the table.
So if tons of slow queries are registered to mysql.slow_log, your `SELECT * from mysql.slow_log` queries also become slow.

### 2. No way to rotate Aurora slowlog table

mysql.slow_log table on RDS mysql can be purged by using `CALL mysql.rds_rotate_slow_log`. On the other hand, the stored procedure executed on Aurora makes following error.

```
> CALL mysql.rds_rotate_slow_log;
ERROR 1289 (HY000): The 'CSV' feature is disabled; you need MySQL built with 'CSV' to have it working
```

According to the above reasons, I have implemented input plugin with `log_output=FILE` for Aurora.

## Installation

```ruby
$ fluent-gem install fluent-plugin-aurora-slowquerylog --no-document
```

## Input: How It Works
TBW

## Usage
### Sample configuration

```
<source>
  @type aurora_slowquerylog
  tag  aurora.slowlog
  db_instance_identifier  aurora_node_id
  region  us-east-1
  log_file_name  slowquery/mysql-slowquery.log
  aurora_state_file  /var/run/fluentd/aurora_state
  log_fetch_interval  30 #optionnal
  aws_access_key_id  your_aws_access_key_id #optionnal
  aws_secret_access_key  your_aws_secret_access_key #optionnal
  filename_contains mysql-slowquery.log # default 'mysql-slowquery.log'
</source>
```

* **tag** tag name of events
* **db_instance_identifier** AWS Aurora node id
* **region** AWS region name
* **log_file_name** RDS slowlog name. Currently we cannot change file name from 'slowquery/mysql-slowquery.log'
* **aurora_state_file** state file that keeps maker information and current & last slowquery log name
* **log_fetch_interval** interval time(second) for log fetch (optional)
* **aws_access_key_id** AWS access key id. For AWS user IAM instance profile is recommended without using this option (optional)
* **aws_secret_access_key** AWS secret access key. For AWS user IAM instance profile is recommended without using this option (optional)
* **filename_contains** filter condition for fetching slow query log (optional)


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/fluent-plugin-aurora-slowquerylog.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

