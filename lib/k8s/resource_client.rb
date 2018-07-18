module K8s
  class ResourceClient
    module Utils
      # @param selector [nil, String, Hash{String => String}]
      # @return [nil, String]
      def selector_query(selector)
        case selector
        when nil
          nil
        when String
          selector
        when Hash
          selector.map{|k, v| "#{k}=#{v}"}.join ','
        else
          fail "Invalid selector type. #{selector.inspect}"
        end
      end

      # @param options [Hash]
      # @return [Hash, nil]
      def make_query(options)
        query = options.compact

        return nil if query.empty?

        query
      end
    end

    include Utils
    extend Utils

    # Pipeline list requests for multiple resource types.
    #
    # Returns flattened array with mixed resource kinds.
    #
    # @param resources [Array<K8s::ResourceClient>]
    # @param transport [K8s::Transport]
    # @param namespace [String, nil]
    # @param labelSelector [nil, String, Hash{String => String}]
    # @param fieldSelector [nil, String, Hash{String => String}]
    # @return [Array<K8s::Resource>]
    def self.list(resources, transport, namespace: nil, labelSelector: nil, fieldSelector: nil)
      api_paths = resources.map{|resource| resource.path(namespace: namespace) }
      api_lists = transport.gets(*api_paths,
         response_class: K8s::API::MetaV1::List,
         query: make_query(
           'labelSelector' => selector_query(labelSelector),
           'fieldSelector' => selector_query(fieldSelector),
         ),
       )

      resources.zip(api_lists).map {|resource, api_list| resource.process_list(api_list) }.flatten
    end

    # @param transport [K8s::Transport]
    # @param api_client [K8s::APIClient]
    # @param api_resource [K8s::API::MetaV1::APIResource]
    # @param namespace [String]
    def initialize(transport, api_client, api_resource, namespace: nil, resource_class: K8s::Resource)
      @transport = transport
      @api_client = api_client
      @api_resource = api_resource
      @namespace = namespace
      @resource_class = resource_class

      if @api_resource.name.include? '/'
        @resource, @subresource = @api_resource.name.split('/', 2)
      else
        @resource = @api_resource.name
        @subresource = nil
      end

      fail "Resource #{api_resource.name} is not namespaced" if namespace unless api_resource.namespaced
    end

    # @return [String]
    def api_version
      @api_client.api_version
    end

    # @return [String] resource or resource/subresource
    def name
      @api_resource.name
    end

    # @return [String, nil]
    def namespace
      @namespace
    end

    # @return [String]
    def resource
      @resource
    end

    # @return [String, nil]
    def subresource
      @subresource
    end

    # @return [String]
    def kind
      @api_resource.kind
    end

    # @return [class] K8s::Resource
    def resource_class
      @resource_class
    end

    # @return [Bool]
    def namespaced?
      !!@api_resource.namespaced
    end

    # @return [String]
    def path(name = nil, subresource: @subresource, namespace: @namespace)
      namespace_part = namespace ? ['namespaces', namespace] : []

      if name && subresource
        @api_client.path(*namespace_part, @resource, name, subresource)
      elsif name
        @api_client.path(*namespace_part, @resource, name)
      else
        @api_client.path(*namespace_part, @resource)
      end
    end

    # @return [Bool]
    def create?
      @api_resource.verbs.include? 'create'
    end

    # @param resource [resource_class] with metadata.namespace and metadata.name set
    # @return [resource_class]
    def create_resource(resource)
      @transport.request(
        method: 'POST',
        path: self.path(namespace: resource.metadata.namespace),
        request_object: resource,
        response_class: @resource_class,
      )
    end

    # @return [Bool]
    def get?
      @api_resource.verbs.include? 'get'
    end

    # @return [resource_class]
    def get(name, namespace: @namespace)
      @transport.request(
        method: 'GET',
        path: self.path(name, namespace: namespace),
        response_class: @resource_class,
      )
    end

    # @param resource [resource_class]
    # @return [resource_class]
    def get_resource(resource)
      @transport.request(
        method: 'GET',
        path: self.path(resource.metadata.name, namespace: resource.metadata.namespace),
        response_class: @resource_class,
      )
    end

    # @return [Bool]
    def list?
      @api_resource.verbs.include? 'list'
    end

    # @param list [K8s::API::MetaV1::List]
    # @return [Array<resource_class>]
    def process_list(list)
      list.items.map {|item|
        # list items omit kind/apiVersion
        @resource_class.new(item.merge('apiVersion' => list.apiVersion, 'kind' => @api_resource.kind))
      }
    end

    # @param labelSelector [nil, String, Hash{String => String}]
    # @param fieldSelector [nil, String, Hash{String => String}]
    # @return [Array<resource_class>]
    def list(labelSelector: nil, fieldSelector: nil, namespace: @namespace)
      list = @transport.request(
        method: 'GET',
        path: self.path(namespace: namespace),
        response_class: K8s::API::MetaV1::List,
        query: make_query(
          'labelSelector' => selector_query(labelSelector),
          'fieldSelector' => selector_query(fieldSelector),
        ),
      )
      process_list(list)
    end

    # @return [Bool]
    def update?
      @api_resource.verbs.include? 'update'
    end

    # @param resource [resource_class] with metadata.resourceVersion set
    # @return [resource_class]
    def update_resource(resource)
      @transport.request(
        method: 'PUT',
        path: self.path(resource.metadata.name, namespace: resource.metadata.namespace),
        request_object: resource,
        response_class: @resource_class,
      )
    end

    # @return [Bool]
    def delete?
      @api_resource.verbs.include? 'delete'
    end

    # @param name [String]
    # @param namespace [String]
    # @return [K8s::API::MetaV1::Status]
    def delete(name, namespace: @namespace, propagationPolicy: nil)
      @transport.request(
        method: 'DELETE',
        path: self.path(name, namespace: namespace),
        query: make_query(
          'propagationPolicy' => propagationPolicy,
        ),
        response_class: @resource_class, # XXX: documented as returning Status
      )
    end

    # @param namespace [String]
    # @param labelSelector [nil, String, Hash{String => String}]
    # @param fieldSelector [nil, String, Hash{String => String}]
    # @return [K8s::API::MetaV1::Status]
    def delete_collection(namespace: @namespace, labelSelector: nil, fieldSelector: nil, propagationPolicy: nil)
      list = @transport.request(
        method: 'DELETE',
        path: self.path(namespace: namespace),
        query: make_query(
          'labelSelector' => selector_query(labelSelector),
          'fieldSelector' => selector_query(fieldSelector),
          'propagationPolicy' => propagationPolicy,
        ),
        response_class: K8s::API::MetaV1::List, # XXX: documented as returning Status
      )
      process_list(list)
    end

    # @param resource [resource_class] with metadata
    # @return [K8s::API::MetaV1::Status]
    def delete_resource(resource, **options)
      delete(resource.metadata.name, namespace: resource.metadata.namespace, **options)
    end
  end
end