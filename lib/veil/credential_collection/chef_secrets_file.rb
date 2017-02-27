require "veil/credential_collection/base"
require "fileutils"
require "json"
require "tempfile"

module Veil
  class CredentialCollection
    class ChefSecretsFile < Base
      class << self
        def from_file(path)
          hash = JSON.parse(IO.read(path), symbolize_names: true)

          if hash.key?(:veil) && hash[:veil][:type] == "Veil::CredentialCollection::ChefSecretsFile"
            creds = new(Veil::Utils.symbolize_keys(hash[:veil]))
          else
            creds = new
            creds.import_legacy_credentials(hash)
          end

          creds.path = path
          creds

        rescue JSON::ParserError, Errno::ENOENT => e
          raise InvalidCredentialCollectionFile.new("#{path} is not a valid credentials file:\n #{e.message}")
        end
      end

      attr_reader :path, :user, :group

      # Create a new ChefSecretsFile
      #
      # @param [Hash] opts
      #   a hash of options to pass to the constructor
      def initialize(opts = {})
        @path    = (opts[:path] && File.expand_path(opts[:path])) || "/etc/opscode/private-chef-secrets.json"
        @user    = opts[:user]    || 'root'
        @group   = opts[:group]   || 'root'
        @version = opts[:version] || 1
        super(opts)
      end

      # Set the secrets file path
      #
      # @param [String] path
      #   a path to the private-chef-secrets.json
      def path=(path)
        @path = File.expand_path(path)
      end

      # Save the CredentialCollection to file
      def save
        FileUtils.mkdir_p(File.dirname(path)) unless File.directory?(File.dirname(path))

        f = Tempfile.new("veil") # defaults to mode 0600
        FileUtils.chown(user, group, f.path)
        f.puts(JSON.pretty_generate(secrets_hash))
        f.flush
        f.close

        FileUtils.mv(f.path, path)
        true
      end

      # Return the instance as a secrets style hash
      def secrets_hash
        { "veil" => to_h }.merge(legacy_credentials_hash)
      end

      # Return the credentials in a legacy chef secrets hash
      def legacy_credentials_hash
        hash = Hash.new

        to_h[:credentials].each do |namespace, creds|
          hash[namespace] = {}
          creds.each { |name, cred| hash[namespace][name] = cred[:value] }
        end

        hash
      end

      def import_legacy_credentials(hash)
        hash.each do |namespace, creds_hash|
          credentials[namespace.to_s] ||= Hash.new
          creds_hash.each do |cred, value|
            credentials[namespace.to_s][cred.to_s] = Veil::Credential.new(
              name: cred.to_s,
              value: value,
              length: value.length
            )
          end
        end
      end
    end
  end
end
