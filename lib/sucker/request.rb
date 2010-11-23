require "typhoeus"
require "ostruct"
require "uri"

module Sucker #:nodoc:

  # A wrapper around the API request
  class Request
    HOSTS = {
      :us  => 'ecs.amazonaws.com',
      :uk  => 'ecs.amazonaws.co.uk',
      :de  => 'ecs.amazonaws.de',
      :ca  => 'ecs.amazonaws.ca',
      :fr  => 'ecs.amazonaws.fr',
      :jp  => 'ecs.amazonaws.jp' }
    PATH = "/onca/xml"

    # The Amazon locale to query
    attr_accessor :locale

    # The Amazon secret access key
    attr_accessor :secret

    # The hash of parameters to query Amazon with
    attr_accessor :parameters

    # Initializes a request object
    #
    #   worker = Sucker.new(
    #     :locale => "us",
    #     :key    => "API KEY",
    #     :secret => "API SECRET")
    #
    def initialize(args)
      self.parameters = {
        "Service" => "AWSECommerceService",
        "Version" => CURRENT_AMAZON_API_VERSION
      }

      args.each { |k, v| send("#{k}=", v) }
    end

    # Merges a hash into existing parameters
    #
    #   worker = Sucker.new
    #   worker << {
    #     "Operation"     => "ItemLookup",
    #     "IdType"        => "ASIN",
    #     "ItemId"        => "0816614024",
    #     "ResponseGroup" => "ItemAttributes" }
    #
    def <<(hash)
      self.parameters.merge!(hash)
    end

    # Returns the associate tag for the current locale
    def associate_tag
      @associate_tags[locale.to_sym] rescue nil
    end

    # Sets the associate tag for the current locale
    #
    #   worker = Sucker.new
    #   worker.associate_tag = 'foo-bar'
    #
    def associate_tag=(token)
      @associate_tags ||= {}
      @associate_tags[locale.to_sym] = token
    end

    # Sets associate tags for all locales
    #
    # You need a distinct associate tag for each locale.
    #
    #    tags = {
    #      :us => 'foo-bar-10',
    #      :uk => 'foo-bar-20',
    #      :de => 'foo-bar-30',
    #      ... }
    #
    #    worker = Sucker.new
    #    worker.associate_tags = tags
    #
    def associate_tags=(tokens)
      @associate_tags = tokens
    end

    # Performs a request and returns a response
    #
    #   worker = Sucker.new
    #   response = worker.get
    #
    def get
      raise ArgumentError.new "Locale missing"         unless locale
      raise ArgumentError.new "AWS access key missing" unless key

      response = Typhoeus::Request.get(uri.to_s)
      Response.new(response)
    end

    # Performs a request for all locales, returns an array of responses, and yields
    # them if given a block
    #
    #    worker = Sucker.new
    #
    #    # This blocks until all requests are complete
    #    responses = worker.get_all
    #
    #    # This does not block
    #    worker.get_all do |response|
    #      process_response
    #    end
    #
    def get_all
      uris = HOSTS.keys.map do |locale|
        self.locale = locale
        uri.to_s
      end
      
      responses = []
      
      uris.each do |uri|
        request = Typhoeus::Request.new(uri)
        request.on_complete { |response| responses << Response.new(response) }
        hydra.queue(request)
      end

      hydra.run
      responses
    end

    # Returns the AWS access key for the current locale
    def key
      @keys[locale.to_sym]
    end

    # Sets a global AWS access key ID
    #
    #   worker = Sucker.new
    #   worker.key = 'foo'
    #
    def key=(token)
      @keys = HOSTS.keys.inject({}) do |keys, locale|
        keys[locale] = token
        keys
      end
    end

    # Sets distinct AWS access keys for the locales
    #
    # You can use the same key on multiple venues. Caveat: Calls against (1) the US
    # and Canada and (2) the UK, France, and Germany count against the same call
    # rate quota.
    #
    #    #   keys = {
    #     :us => 'foo',
    #     :uk => 'bar',
    #     :de => 'baz',
    #     ... }
    #
    #   worker = Sucker.new
    #   worker.keys = keys
    #
    def keys=(tokens)
      @keys = tokens
    end

    # Sets the Amazon API version
    #
    #   worker = Sucker.new
    #   worker.version = '2010-06-01'
    #
    def version=(version)
      self.parameters["Version"] = version
    end
    
    # This is due to laziness / hackiness
    def search(query, indexes = [])
      responses = []
      
      indexes.each do |index|
        self.parameters.merge!({
          "Operation" => "ItemSearch", 
          "SearchIndex" => index, 
          "Keywords" => query,
          "ResponseGroup" => "Small,Images,SalesRank"
        })

        request = Typhoeus::Request.new(self.uri.to_s)
        request.on_complete { |response| responses << Response.new(response) }
        hydra.queue(request)
      end  

      hydra.run
      responses
    end

    private
    
    # Typhoeus hydra
    def hydra
      @hydra ||= Typhoeus::Hydra.new
    end

    # Timestamps parameters and concatenates them into a query string
    def build_query
      parameters.
        merge(timestamp).
        merge({ "AWSAccessKeyId" => key }).
        merge({ "AssociateTag"   => associate_tag }).
        sort.
        collect do |k, v|
          "#{k}=" + escape(v.is_a?(Array) ? v.join(",") : v.to_s)
        end.
        join("&")
    end

    # Returns a signed and timestamped query string
    def build_signed_query
      query = build_query

      digest = OpenSSL::Digest::Digest.new("sha256")
      string = ["GET", host, PATH, query].join("\n")
      hmac = OpenSSL::HMAC.digest(digest, secret, string)

      query + "&Signature=" + escape([hmac].pack("m").chomp)
    end

    # Plagiarized from the Ruby CGI library via ruby_aaws
    def escape(string)
      string.gsub( /([^a-zA-Z0-9_.~-]+)/ ) do
        '%' + $1.unpack( 'H2' * $1.bytesize ).join( '%' ).upcase
      end
    end

    def host
      HOSTS[locale.to_sym]
    end

    def uri
      URI::HTTP.build(
        :host   => host,
        :path   => PATH,
        :query  => build_signed_query)
    end

    def timestamp
      { "Timestamp" => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ') }
    end
  end
end
