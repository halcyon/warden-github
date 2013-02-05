module Warden
  module GitHub
    class Strategy < ::Warden::Strategies::Base
      SESSION_KEY = 'warden.github.oauth'

      # The first time this is called, the flow gets set up, stored in the
      # session and the user gets redirected to GitHub to perform the login.
      #
      # When this is called a second time, the flow gets evaluated, the code
      # gets exchanged for a token, and the user gets loaded and passed to
      # warden.
      #
      # If anything goes wrong, the flow is aborted and reset, and warden gets
      # notified about the failure.
      #
      # Once the user gets set, warden invokes the after_authentication callback
      # that handles the redirect to the originally requested url and cleans up
      # the flow. Note that this is done in a hook because setting a user
      # (through #success!) and redirecting (through #redirect!) inside the
      # #authenticate! method are mutual exclusive.
      def authenticate!
        if in_flow?
          continue_flow!
        else
          begin_flow!
        end
      end

      # This is called by the after_authentication hook which is invoked after
      # invoking #success!.
      def finalize_flow!
        redirect!(custom_session['return_to'])
        teardown_flow
        throw(:warden)
      end

      private

      def setup_flow
        custom_session['state'] = state
        custom_session['return_to'] = request.url
      end

      def begin_flow!
        setup_flow
        redirect!(oauth.authorize_uri.to_s)
        throw(:warden)
      end

      def continue_flow!
        validate_flow!
        success!(load_user)
      end

      def abort_flow!(message)
        teardown_flow
        fail!(message)
        throw(:warden)
      end

      def teardown_flow
        session.delete(SESSION_KEY)
      end

      def in_flow?
        !custom_session.empty? && params['state'] && params['code']
      end

      def validate_flow!
        abort_flow!('State mismatch') unless valid_state?
      end

      def valid_state?
        params['state'] == state
      end

      def custom_session
        session[SESSION_KEY] ||= {}
      end

      def load_user
        User.load(oauth.access_token)
      rescue OAuth::BadVerificationCode => e
        abort_flow!(e.message)
      end

      def state
        @state ||=
          custom_session['state'] ||
          Digest::SHA1.hexdigest(rand(36**8).to_s(36))
      end

      def oauth
        @oauth ||= OAuth.new(
          :code          => params['code'],
          :state         => state,
          :scope         => env['warden'].config[:github_scopes],
          :client_id     => env['warden'].config[:github_client_id],
          :client_secret => env['warden'].config[:github_secret],
          :redirect_uri  => redirect_uri)
      end

      def redirect_uri
        absolute_uri(request, callback_path, env['HTTP_X_FORWARDED_PROTO'])
      end

      def callback_path
        env['warden'].config[:github_callback_url] || request.path
      end

      def absolute_uri(request, suffix = nil, proto = "http")
        port_part = case request.scheme
                    when "http"
                      request.port == 80 ? "" : ":#{request.port}"
                    when "https"
                      request.port == 443 ? "" : ":#{request.port}"
                    end

        proto = "http" if proto.nil?
        "#{proto}://#{request.host}#{port_part}#{suffix}"
      end
    end
  end
end

Warden::Strategies.add(:github, Warden::GitHub::Strategy)
