require "active_support/xml_mini/nokogiri"

module Sucker #:nodoc:

  # A Nokogiri-driven wrapper around the cURL response
  class Response

    # The response body
    attr_accessor :body

    # The HTTP status code of the response
    attr_accessor :code

    # Transaction time in seconds for request
    attr_accessor :time

    # The request URI
    attr_accessor :uri

    def initialize(response)
      self.body = response.body
      self.code = response.code
      self.time = response.time
      self.uri  = response.effective_url
    end

    # A shorthand that yields each match to a block
    #
    #   worker.get.each("Item") { |item| process(item) }
    #
    def each(path)
      find(path).each { |e| yield e }
    end

    # Queries an xpath and returns an array of matching nodes
    #
    #   response = worker.get
    #   response.find("Item").each { |item| ... }
    #
    def find(path)
      xml.xpath("//xmlns:#{path}").map { |e| strip_content(e.to_hash[path]) }
    end

    # A shorthand that yields matches to a block and collects returned values
    #
    #   descriptions = worker.get.map("Item") { |item| build_description(item) }
    #
    def map(path)
      find(path).map { |e| yield e }
    end

    def node(path) # :nodoc:
      warn "[DEPRECATION] `node` is deprecated.  Use `find` instead."
      find(path)
    end

    # Parses the response into a simple hash
    #
    #   response = worker.get
    #   response.to_hash
    #
    def to_hash
      strip_content(xml.to_hash)
    end

    # Checks if the HTTP response is OK
    #
    #    response = worker.get
    #    p response.valid?
    #    => true
    #
    def valid?
      code == 200
    end

    # The XML document
    #
    #    response = worker.get
    #    response.xml
    def xml
      @xml ||= Nokogiri::XML(body)
    end

    private

    # Let's massage that hash
    def strip_content(node)
      case node
      when Array
        node.map { |child| strip_content(child) }
      when Hash
        if node.keys.size == 1 && node["__content__"]
          node["__content__"]
        else
          node.inject({}) do |attributes, key_value|
            attributes.merge({ key_value.first => strip_content(key_value.last) })
          end
        end
      else
        node
      end
    end
  end
end
