require 'test_helper'

class AuthenticationSanityTest < ActionController::IntegrationTest
  test 'home should be accessible without sign in' do
    visit '/'
    assert_response :success
    assert_template 'home/index'
  end

  test 'sign in as user should not authenticate admin scope' do
    sign_in_as_user
    assert warden.authenticated?(:user)
    assert_not warden.authenticated?(:admin)
  end

  test 'sign in as admin should not authenticate user scope' do
    sign_in_as_admin
    assert warden.authenticated?(:admin)
    assert_not warden.authenticated?(:user)
  end

  test 'sign in as both user and admin at same time' do
    sign_in_as_user
    sign_in_as_admin
    assert warden.authenticated?(:user)
    assert warden.authenticated?(:admin)
  end

  test 'sign out as user should not touch admin authentication if sign_out_all_scopes is false' do
    swap Devise, :sign_out_all_scopes => false do
      sign_in_as_user
      sign_in_as_admin
      get destroy_user_session_path
      assert_not warden.authenticated?(:user)
      assert warden.authenticated?(:admin)
    end
  end

  test 'sign out as admin should not touch user authentication if sign_out_all_scopes is false' do
    swap Devise, :sign_out_all_scopes => false do
      sign_in_as_user
      sign_in_as_admin

      get destroy_admin_session_path
      assert_not warden.authenticated?(:admin)
      assert warden.authenticated?(:user)
    end
  end

  test 'sign out as user should also sign out admin if sign_out_all_scopes is true' do
    swap Devise, :sign_out_all_scopes => true do
      sign_in_as_user
      sign_in_as_admin

      get destroy_user_session_path
      assert_not warden.authenticated?(:user)
      assert_not warden.authenticated?(:admin)
    end
  end

  test 'sign out as admin should also sign out user if sign_out_all_scopes is true' do
    swap Devise, :sign_out_all_scopes => true do
      sign_in_as_user
      sign_in_as_admin

      get destroy_admin_session_path
      assert_not warden.authenticated?(:admin)
      assert_not warden.authenticated?(:user)
    end
  end

  test 'not signed in as admin should not be able to access admins actions' do
    get admins_path
    assert_redirected_to new_admin_session_path
    assert_not warden.authenticated?(:admin)
  end

  test 'not signed in as admin should not be able to access private route restricted to admins' do
    get private_path
    assert_redirected_to new_admin_session_path
    assert_not warden.authenticated?(:admin)
  end

  test 'signed in as user should not be able to access private route restricted to admins' do
    sign_in_as_user
    assert warden.authenticated?(:user)
    assert_not warden.authenticated?(:admin)
    get private_path
    assert_redirected_to new_admin_session_path
  end

  test 'signed in as admin should be able to access private route restricted to admins' do
    sign_in_as_admin
    assert warden.authenticated?(:admin)
    assert_not warden.authenticated?(:user)

    get private_path

    assert_response :success
    assert_template 'home/private'
    assert_contain 'Private!'
  end

  test 'signed in as user should not be able to access admins actions' do
    sign_in_as_user
    assert warden.authenticated?(:user)
    assert_not warden.authenticated?(:admin)

    get admins_path
    assert_redirected_to new_admin_session_path
  end

  test 'signed in as admin should be able to access admin actions' do
    sign_in_as_admin
    assert warden.authenticated?(:admin)
    assert_not warden.authenticated?(:user)

    get admins_path

    assert_response :success
    assert_template 'admins/index'
    assert_contain 'Welcome Admin'
  end

  test 'authenticated admin should not be able to sign as admin again' do
    sign_in_as_admin
    get new_admin_session_path

    assert_response :redirect
    assert_redirected_to admin_root_path
    assert warden.authenticated?(:admin)
  end

  test 'authenticated admin should be able to sign out' do
    sign_in_as_admin
    assert warden.authenticated?(:admin)

    get destroy_admin_session_path
    assert_response :redirect
    assert_redirected_to root_path

    get root_path
    assert_contain 'Signed out successfully'
    assert_not warden.authenticated?(:admin)
  end

  test 'unauthenticated admin does not set message on sign out' do
    get destroy_admin_session_path
    assert_response :redirect
    assert_redirected_to root_path

    get root_path
    assert_not_contain 'Signed out successfully'
  end
end

class AuthenticationRedirectTest < ActionController::IntegrationTest
  test 'redirect from warden shows sign in or sign up message' do
    get admins_path

    warden_path = new_admin_session_path
    assert_redirected_to warden_path

    get warden_path
    assert_contain 'You need to sign in or sign up before continuing.'
  end

  test 'redirect to default url if no other was configured' do
    sign_in_as_user
    assert_template 'home/index'
    assert_nil session[:"user_return_to"]
  end

  test 'redirect to requested url after sign in' do
    get users_path
    assert_redirected_to new_user_session_path
    assert_equal users_path, session[:"user_return_to"]

    follow_redirect!
    sign_in_as_user :visit => false

    assert_current_url '/users'
    assert_nil session[:"user_return_to"]
  end

  test 'redirect to last requested url overwriting the stored return_to option' do
    get expire_user_path(create_user)
    assert_redirected_to new_user_session_path
    assert_equal expire_user_path(create_user), session[:"user_return_to"]

    get users_path
    assert_redirected_to new_user_session_path
    assert_equal users_path, session[:"user_return_to"]

    follow_redirect!
    sign_in_as_user :visit => false

    assert_current_url '/users'
    assert_nil session[:"user_return_to"]
  end

  test 'xml http requests does not store urls for redirect' do
    get users_path, {}, 'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest'
    assert_equal 401, response.status
    assert_nil session[:"user_return_to"]
  end

  test 'redirect to configured home path for a given scope after sign in' do
    sign_in_as_admin
    assert_equal "/admin_area/home", @request.path
  end
end

class AuthenticationSessionTest < ActionController::IntegrationTest
  test 'destroyed account is signed out' do
    sign_in_as_user
    get '/users'

    User.destroy_all
    get '/users'
    assert_redirected_to new_user_session_path
  end

  test 'allows session to be set for a given scope' do
    sign_in_as_user
    get '/users'
    assert_equal "Cart", @controller.user_session[:cart]
  end

  test 'does not explode when invalid user class is stored in session' do
    klass = User
    paths = ActiveSupport::Dependencies.autoload_paths.dup

    begin
      sign_in_as_user
      assert warden.authenticated?(:user)

      Object.send :remove_const, :User
      ActiveSupport::Dependencies.autoload_paths.clear

      visit "/users"
      assert_not warden.authenticated?(:user)
    ensure
      Object.const_set(:User, klass)
      ActiveSupport::Dependencies.autoload_paths.replace(paths)
    end
  end
end

class AuthenticationWithScopesTest < ActionController::IntegrationTest
  test 'renders the scoped view if turned on and view is available' do
    swap Devise, :scoped_views => true do
      assert_raise Webrat::NotFoundError do
        sign_in_as_user
      end
      assert_match /Special user view/, response.body
    end
  end

  test 'renders the scoped view if turned on in an specific controller' do
    begin
      Devise::SessionsController.scoped_views = true
      assert_raise Webrat::NotFoundError do
        sign_in_as_user
      end

      assert_match /Special user view/, response.body
      assert !Devise::PasswordsController.scoped_views?
    ensure
      Devise::SessionsController.send :remove_instance_variable, :@scoped_views
    end
  end

  test 'does not render the scoped view if turned off' do
    swap Devise, :scoped_views => false do
      assert_nothing_raised do
        sign_in_as_user
      end
    end
  end

  test 'does not render the scoped view if not available' do
    swap Devise, :scoped_views => true do
      assert_nothing_raised do
        sign_in_as_admin
      end
    end
  end
end

class AuthenticationOthersTest < ActionController::IntegrationTest
  test 'uses the custom controller with the custom controller view' do
    get '/admin_area/sign_in'
    assert_contain 'Sign in'
    assert_contain 'Welcome to "sessions" controller!'
    assert_contain 'Welcome to "sessions/new" view!'
  end

  test 'render 404 on roles without routes' do
    get '/admin_area/password/new'
    assert_equal 404, response.status
  end

  test 'render 404 on roles without mapping' do
    assert_raise AbstractController::ActionNotFound do
      get '/sign_in'
    end
  end

  test 'sign in with script name' do
    assert_nothing_raised do
      get new_user_session_path, {}, "SCRIPT_NAME" => "/omg"
      fill_in "email", :with => "user@test.com"
    end
  end

  test 'registration in xml format works when recognizing path' do
    assert_nothing_raised do
      post user_registration_path(:format => 'xml', :user => {:email => "test@example.com", :password => "invalid"} )
    end
  end

  test 'uses the mapping from router' do
    sign_in_as_user :visit => "/as/sign_in"
    assert warden.authenticated?(:user)
    assert_not warden.authenticated?(:admin)
  end

  test 'uses the mapping from nested devise_for call' do
    sign_in_as_user :visit => "/devise_for/sign_in"
    assert warden.authenticated?(:user)
    assert_not warden.authenticated?(:admin)
  end
end

class AuthenticationSignOutViaTest < ActionController::IntegrationTest
  def sign_in!(scope)
    sign_in_as_user(:visit => send("new_#{scope}_session_path"))
    assert warden.authenticated?(scope)
  end

  test 'allow sign out via delete when sign_out_via provides only delete' do
    sign_in!(:sign_out_via_delete)
    delete destroy_sign_out_via_delete_session_path
    assert_not warden.authenticated?(:sign_out_via_delete)
  end

  test 'do not allow sign out via get when sign_out_via provides only delete' do
    sign_in!(:sign_out_via_delete)
    get destroy_sign_out_via_delete_session_path
    assert warden.authenticated?(:sign_out_via_delete)
  end

  test 'allow sign out via post when sign_out_via provides only post' do
    sign_in!(:sign_out_via_post)
    post destroy_sign_out_via_post_session_path
    assert_not warden.authenticated?(:sign_out_via_post)
  end

  test 'do not allow sign out via get when sign_out_via provides only post' do
    sign_in!(:sign_out_via_post)
    get destroy_sign_out_via_delete_session_path
    assert warden.authenticated?(:sign_out_via_post)
  end

  test 'allow sign out via delete when sign_out_via provides delete and post' do
    sign_in!(:sign_out_via_delete_or_post)
    delete destroy_sign_out_via_delete_or_post_session_path
    assert_not warden.authenticated?(:sign_out_via_delete_or_post)
  end

  test 'allow sign out via post when sign_out_via provides delete and post' do
    sign_in!(:sign_out_via_delete_or_post)
    post destroy_sign_out_via_delete_or_post_session_path
    assert_not warden.authenticated?(:sign_out_via_delete_or_post)
  end

  test 'do not allow sign out via get when sign_out_via provides delete and post' do
    sign_in!(:sign_out_via_delete_or_post)
    get destroy_sign_out_via_delete_or_post_session_path
    assert warden.authenticated?(:sign_out_via_delete_or_post)
  end
end
