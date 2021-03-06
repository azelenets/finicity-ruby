require 'httparty'
require 'rack/mime'
require 'net/http'

module Finicity
  module Fetchers
    class Base
      include HTTParty

      base_uri 'https://api.finicity.com'
      headers 'Content-Type' => Rack::Mime::MIME_TYPES['.json']
      headers 'Accept' => Rack::Mime::MIME_TYPES['.json']
      headers 'Finicity-App-Key' => Finicity.configs.app_key

      debug_output $stdout if Finicity.configs.verbose

      class << self
        def request(method, endpoint, opts = {})
          tries = 0
          loop do
            begin
              break fetch(method, endpoint, opts)
            rescue Net::ReadTimeout, Errno::ECONNREFUSED, Net::OpenTimeout => e
              raise e if (tries += 1) > Finicity.configs.max_retries.to_i
            end
          end
        end

        def request_download(endpoint)
          tries = 0
          loop do
            begin
              break fetch_download(endpoint)
            rescue Net::ReadTimeout, Errno::ECONNREFUSED, Net::OpenTimeout => e
              raise e if (tries += 1) > Finicity.configs.max_retries.to_i
            end
          end
        end

        protected

        def fetch(method, endpoint, opts)
          request_opts = normalize_request_options(opts)

          response = send(method, endpoint, request_opts)

          raise Finicity::ApiServerError, response.body if server_error?(response)

          Hashie::Mash.new(
            method: method,
            endpoint: endpoint,
            options: request_opts,
            success?: response.success?,
            status_code: response.code,
            body: parse_json(response.body),
            headers: response.headers
          )
        end

        def fetch_download(endpoint)
          uri = URI(endpoint)
          Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
            req = Net::HTTP::Get.new(uri)

            req['Finicity-App-Key'] = Finicity.configs.app_key
            req['Finicity-App-Token'] = ::Finicity::Fetchers::Token.get
            req['Content-Type'] = Rack::Mime::MIME_TYPES['.json']
            req['Accept'] = Rack::Mime::MIME_TYPES['.json']

            http.request(req)
          end
        end

        def normalize_request_options(opts)
          opts.clone.tap do |o|
            o[:headers] = default_headers.merge(o[:headers].to_h)
            o[:body] = jsonify(o[:body]) if o[:body].present?
            o[:query] = camelcase_keys(o[:query]) if o[:query].present?
          end
        end

        def parse_json(body)
          result = JSON.parse(body.to_s).deep_transform_keys!(&:underscore)
          Hashie::Mash.new(result)
        rescue JSON::ParserError
          body
        end

        def jsonify(body)
          camelcase_keys(body).to_json
        end

        def camelcase_keys(hash)
          hash.deep_transform_keys! { |k| k.to_s.camelcase(:lower) }
        end

        def server_error?(response)
          other_content_type?(response)
        end

        def other_content_type?(response)
          content_type = response.headers["Content-Type"]&.downcase

          # /decisioning/xxx resources add on ";charset=utf-8", so we need to account for that
          content_type.present? && content_type !~ /^application\/json(;charset=utf-8$)?/
        end

        def default_headers
          {}
        end
      end
    end
  end
end
