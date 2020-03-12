module Finicity
  module Resources
    class Statement < Base
      # Gets the latest statement
      # https://community.finicity.com/s/article/Statement-Aggregation#get_customer_account_statement
      def get_latest(account_id)
        request_download("https://api.finicity.com/aggregation/v1/customers/#{customer_id}/accounts/#{account_id}/statement")
      end
    end
  end
end
