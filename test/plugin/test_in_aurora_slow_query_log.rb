require 'helper'

class AuroraSlowqueryLogInputTest < Test::Unit::TestCase
  # this is required to setup router and others
  def setup
    Fluent::Test.setup
  end

  # default configuration for tests
  CONFIG = %[
    tag tag.child_tag.test
    db_instance_identifier rds-id
    filename_contains mysql-slowquery.log
    region us-east-1
    log_file_name slowquery/mysql-slowquery.log
    aurora_state_file /tmp/aurora_state
    log_fetch_interval 3
    aws_access_key_id dummy_key_id
    aws_secret_access_key dummy_secret_key
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::InputTestDriver.new(Fluent::AuroraSlowqueryLog).configure(conf)
  end

  sub_test_case 'configured with valid configurations' do
    test 'designated configurations are set correctly' do
      d = create_driver
      assert_equal "tag.child_tag.test", d.instance.tag
      assert_equal "dummy_key_id", d.instance.aws_access_key_id
      assert_equal "dummy_secret_key", d.instance.aws_secret_access_key
      assert_equal "us-east-1", d.instance.region
      assert_equal "rds-id", d.instance.db_instance_identifier
      assert_equal "slowquery/mysql-slowquery.log", d.instance.log_file_name
      assert_equal 3.0, d.instance.log_fetch_interval
      assert_equal "/tmp/aurora_state", d.instance.aurora_state_file
    end
  end

  ## ** Please remove comment out if you want to fetch data from RDS **
  # sub_test_case 'fetch Aurora slowlog data' do
  #   test 'slowlog emit' do
  #     d = create_driver
  #     d.run
  #     p d.emits
  #   end
  # end
end
