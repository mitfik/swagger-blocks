require 'json'
require 'swagger/rails/version'

module Swagger::Rails

  def self.included(base)
    base.extend(ClassMethods)
  end

  # Some custom error classes.
  class Error < Exception; end
  class DeclarationError < Error; end

  def self.build_root_json(swaggered_classes)
    # Get all the nodes from all the classes.
    resource_listing_nodes = []
    api_nodes = []
    swaggered_classes.each do |swaggered_class|
      # next if !swaggered_class.respond_to?(:_swagger_nodes)
      swagger_nodes = swaggered_class.send(:_swagger_nodes)
      resource_listing_node = swagger_nodes[:resource_listing]
      resource_listing_nodes << resource_listing_node if resource_listing_node
      api_nodes += swagger_nodes[:apis]
    end

    if resource_listing_nodes.length == 0
      raise Swagger::Rails::DeclarationError.new(
        'swagger_resource_listing must be declared')
    elsif resource_listing_nodes.length > 1
      raise Swagger::Rails::DeclarationError.new(
        'Only one swagger_resource_listing declaration is allowed.')
    end
    resource_listing_node = resource_listing_nodes.first

    # Build a ResourceNode for every ApiNode and inject it into the resource listing.
    api_nodes.each do |api_node|
      resource_listing_node.api do
        key :path, api_node.data[:path]
        key :description, api_node.data[:description]
      end
    end

    resource_listing_node.as_json
  end

  def self.build_api_json(api_name, swaggered_classes)
  end

  module ClassMethods
    private

    def swagger_resource_listing(&block)
      @swagger_resource_listing_node ||= Swagger::Rails::ResourceListingNode.call(&block)
    end

    def swagger_api_root(name, &block)
      # Evaluate the block in the ApiNode.
      api_node = Swagger::Rails::ApiNode.call(&block)
      @swagger_api_nodes ||= []
      @swagger_api_nodes << api_node

      # Store an internal map from name to ApiNode so that swagger_api_operation blocks with the
      # same name are merged into their parent api.
      @swagger_name_to_api_node ||= {}
      @swagger_name_to_api_node[name] = api_node
    end

    def swagger_api_operation(name, &block)
      if !@swagger_name_to_api_node || !@swagger_name_to_api_node[name]
        raise Swagger::Rails::DeclarationError.new(
          'swagger_api_root must be declared before swagger_api_operation and names must match')
      end
      @swagger_name_to_api_node[name].operation(&block)
    end

    def _swagger_nodes
      @swagger_resource_listing_node ||= nil  # Avoid initialization warning.
      {
        resource_listing: @swagger_resource_listing_node,
        apis: @swagger_api_nodes || [],
      }
    end
  end

  # -----

  # Base node for representing every object in the Swagger DSL.
  class Node
    attr_accessor :name

    def self.call(name: nil, &block)
      # Create a new instance and evaluate the block into it.
      instance = new
      instance.instance_eval(&block)

      # Set the first parameter given as the name.
      instance.name = name if name
      instance
    end

    def as_json
      result = {}
      self.data.each do |key, value|
        if value.is_a?(Node)
          result[key] = value.as_json
        elsif value.is_a?(Array)
          result[key] = []
          value.each do |v|
            result[key] << v.as_json
          end
        else
          result[key] = value
        end
      end
      return result if !name
      # If "name" is given to this node, wrap the data with a root element with the given name.
      {name => result}
    end

    def data
      @data ||= {}
    end

    def key(key, value)
      self.data[key] = value
    end
  end

  # -----
  # Nodes for the Resource Listing.
  # -----

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#51-resource-listing
  class ResourceListingNode < Node
    def info(&block)
      self.data[:info] = InfoNode.call(&block)
    end

    def authorization(name, &block)
      self.data[:authorizations] ||= AuthorizationsNode.new
      self.data[:authorizations].authorization(name, &block)
    end

    def api(&block)
      self.data[:apis] ||= []
      self.data[:apis] << ResourceNode.call(&block)
    end
  end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#512-resource-object
  class ResourceNode < Node; end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#514-authorizations-object
  class AuthorizationsNode < Node
    def authorization(name, &block)
      self.data[name] = AuthorizationNode.call(&block)
    end
  end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#513-info-object
  class AuthorizationNode < Node
    GRANT_TYPES = [:implicit, :authorization_code].freeze

    def scope(&block)
      self.data[:scopes] ||= []
      self.data[:scopes] << ScopeNode.call(&block)
    end

    def grant_type(name, &block)
      raise ArgumentError.new("#{name} not in #{GRANT_TYPES}") if !GRANT_TYPES.include?(name)
      self.data[:grantTypes] ||= GrantTypesNode.new
      self.data[:grantTypes].implicit(&block) if name == :implicit
      self.data[:grantTypes].authorization_code(&block) if name == :authorization_code
    end
  end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#513-info-object
  class InfoNode < Node; end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#516-scope-object
  class ScopeNode < Node; end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#517-grant-types-object
  class GrantTypesNode < Node
    def implicit(&block)
      self.data[:implicit] = ImplicitNode.call(&block)
    end

    def authorization_code(&block)
      self.data[:authorization_code] = AuthorizationCodeNode.call(&block)
    end
  end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#518-implicit-object
  class ImplicitNode < Node
    def login_endpoint(&block)
      self.data[:loginEndpoint] = LoginEndpointNode.call(&block)
    end
  end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#5110-login-endpoint-object
  class LoginEndpointNode < Node; end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#519-authorization-code-object
  class AuthorizationCodeNode < Node
    def token_request_endpoint(&block)
      self.data[:tokenRequestEndpoint] = TokenRequestEndpointNode.call(&block)
    end

    def token_endpoint(&block)
      self.data[:tokenEndpoint] = TokenEndpointNode.call(&block)
    end
  end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#5111-token-request-endpoint-object
  class TokenRequestEndpointNode < Node; end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#5112-token-endpoint-object
  class TokenEndpointNode < Node; end

  # -----
  # Nodes for API Declarations.
  # -----

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#42-file-structure
  class ApiNode < Node
    def operation(&block)
      self.data[:operations] ||= []
      self.data[:operations] << OperationNode.call(&block)
    end
  end

  class OperationNode < Node
    def parameter(&block)
      self.data[:parameters] ||= []
      self.data[:parameters] << ParameterNode.call(&block)
    end

    def response_message(&block)
      self.data[:responseMessages] ||= []
      self.data[:responseMessages] << Node.call(&block)
    end
  end

  # https://github.com/wordnik/swagger-spec/blob/master/versions/1.2.md#524-parameter-object
  class ParameterNode < Node; end
end
