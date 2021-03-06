# Redmine - project management software
# Copyright (C) 2006-2011  See readme for details and license
#

require File.dirname(__FILE__) + '/../test_helper'
require 'projects_controller'

# Re-raise errors caught by the controller.
class ProjectsController; def rescue_action(e) raise e end; end

class ProjectsControllerTest < ActionController::TestCase
  fixtures :projects, :versions, :users, :roles, :members, :member_roles, :issues, :journals, :journal_details,
           :trackers, :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :boards, :messages,
           :attachments, :custom_fields, :custom_values, :time_entries

  def setup
    @controller = ProjectsController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
    @request.session[:user_id] = nil
    Setting.default_language = 'en'
  end
  
  def test_index_routing
    assert_routing(
      {:method => :get, :path => '/projects'},
      :controller => 'projects', :action => 'index'
    )
  end
  
  def test_index
    get :index
    assert_response :success
    assert_template 'index'
    assert_not_nil assigns(:projects)
    
    assert_tag :ul, :child => {:tag => 'li',
                               :descendant => {:tag => 'a', :content => 'eCookbook'},
                               :child => { :tag => 'ul',
                                           :descendant => { :tag => 'a',
                                                            :content => 'Child of private child'
                                                           }
                                          }
                               }
                               
    assert_no_tag :a, :content => /Private child of eCookbook/
  end
  
  def test_index_atom_routing
    assert_routing(
      {:method => :get, :path => '/projects.atom'},
      :controller => 'projects', :action => 'index', :format => 'atom'
    )
  end
  
  def test_index_atom
    get :index, :format => 'atom'
    assert_response :success
    assert_template 'common/feed.atom.rxml'
    assert_select 'feed>title', :text => 'Redmine: Latest workstreams'
    assert_select 'feed>entry', :count => Project.count(:conditions => Project.visible_by(User.current))
  end
  
  def test_add_routing
    assert_routing(
      {:method => :get, :path => '/projects/new'},
      :controller => 'projects', :action => 'add'
    )
    assert_recognizes(
      {:controller => 'projects', :action => 'add'},
      {:method => :post, :path => '/projects/new'}
    )
    assert_recognizes(
      {:controller => 'projects', :action => 'add'},
      {:method => :post, :path => '/projects'}
    )
  end
  
  context "#add" do
    context "by admin user" do
      setup do
        @request.session[:user_id] = 1
      end
      
      should "accept get" do
        get :add
        assert_response :success
        assert_template 'add'
      end
      
      should "accept post" do
        post :add, :project => { :name => "blog", 
                                 :description => "weblog",
                                 :identifier => "blog",
                                 :is_public => 1,
                                 :custom_field_values => { '3' => 'Beta' }
                                }
        assert_redirected_to '/projects/blog/settings'
        
        project = Project.find_by_name('blog')
        assert_kind_of Project, project
        assert_equal 'weblog', project.description 
        assert_equal true, project.is_public?
        assert_nil project.parent
      end
      
      should "accept post with parent" do
        post :add, :project => { :name => "blog", 
                                 :description => "weblog",
                                 :identifier => "blog",
                                 :is_public => 1,
                                 :custom_field_values => { '3' => 'Beta' },
                                 :parent_id => 1
                                }
        assert_redirected_to '/projects/blog/settings'
        
        project = Project.find_by_name('blog')
        assert_kind_of Project, project
        assert_equal Project.find(1), project.parent
      end
    end
    
    context "by non-admin user with add_project permission" do
      setup do
        Role.non_member.add_permission! :add_project
        @request.session[:user_id] = 9
      end
      
      should "accept get" do
        get :add
        assert_response :success
        assert_template 'add'
        assert_no_tag :select, :attributes => {:name => 'project[parent_id]'}
      end
      
      should "accept post" do
        post :add, :project => { :name => "blog", 
                                 :description => "weblog",
                                 :identifier => "blog",
                                 :is_public => 1,
                                 :custom_field_values => { '3' => 'Beta' }
                                }
        
        assert_redirected_to '/projects/blog/settings'
        
        project = Project.find_by_name('blog')
        assert_kind_of Project, project
        assert_equal 'weblog', project.description 
        assert_equal true, project.is_public?
        
        # User should be added as a project member
        assert User.find(9).member_of?(project)
        assert_equal 1, project.all_members.size
      end
      
      should "fail with parent_id" do
        assert_no_difference 'Project.count' do
          post :add, :project => { :name => "blog", 
                                   :description => "weblog",
                                   :identifier => "blog",
                                   :is_public => 1,
                                   :custom_field_values => { '3' => 'Beta' },
                                   :parent_id => 1
                                  }
        end
        assert_response :success
        project = assigns(:project)
        assert_kind_of Project, project
        assert_not_nil project.errors.on(:parent_id)
      end
    end
    
    context "by non-admin user with add_subprojects permission" do
      setup do
        Role.find(1).remove_permission! :add_project
        Role.find(1).add_permission! :add_subprojects
        @request.session[:user_id] = 2
      end
      
      should "accept get" do
        get :add, :parent_id => 'ecookbook'
        assert_response :success
        assert_template 'add'
        # parent project selected
        assert_tag :select, :attributes => {:name => 'project[parent_id]'},
                            :child => {:tag => 'option', :attributes => {:value => '1', :selected => 'selected'}}
        # no empty value
        assert_no_tag :select, :attributes => {:name => 'project[parent_id]'},
                               :child => {:tag => 'option', :attributes => {:value => ''}}
      end
      
      should "accept post with parent_id" do
        post :add, :project => { :name => "blog", 
                                 :description => "weblog",
                                 :identifier => "blog",
                                 :is_public => 1,
                                 :custom_field_values => { '3' => 'Beta' },
                                 :parent_id => 1
                                }
        assert_redirected_to '/projects/blog/settings'
        project = Project.find_by_name('blog')
      end
      
      should "fail without parent_id" do
        assert_no_difference 'Project.count' do
          post :add, :project => { :name => "blog", 
                                   :description => "weblog",
                                   :identifier => "blog",
                                   :is_public => 1,
                                   :custom_field_values => { '3' => 'Beta' }
                                  }
        end
        assert_response :success
        project = assigns(:project)
        assert_kind_of Project, project
        assert_not_nil project.errors.on(:parent_id)
      end
      
      should "fail with unauthorized parent_id" do
        assert !User.find(2).member_of?(Project.find(6))
        assert_no_difference 'Project.count' do
          post :add, :project => { :name => "blog", 
                                   :description => "weblog",
                                   :identifier => "blog",
                                   :is_public => 1,
                                   :custom_field_values => { '3' => 'Beta' },
                                   :parent_id => 6
                                  }
        end
        assert_response :success
        project = assigns(:project)
        assert_kind_of Project, project
        assert_not_nil project.errors.on(:parent_id)
      end
    end
  end
  
  def test_show_routing
    assert_routing(
      {:method => :get, :path => '/projects/test'},
      :controller => 'projects', :action => 'show', :id => 'test'
    )
  end
  
  def test_show_by_id
    get :show, :id => 1
    assert_response :success
    assert_template 'show'
    assert_not_nil assigns(:project)
  end

  def test_show_by_identifier
    get :show, :id => 'ecookbook'
    assert_response :success
    assert_template 'show'
    assert_not_nil assigns(:project)
    assert_equal Project.find_by_identifier('ecookbook'), assigns(:project)
  end
  
  def test_show_should_not_fail_when_custom_values_are_nil
    project = Project.find_by_identifier('ecookbook')
    project.custom_values.first.update_attribute(:value, nil)
    get :show, :id => 'ecookbook'
    assert_response :success
    assert_template 'show'
    assert_not_nil assigns(:project)
    assert_equal Project.find_by_identifier('ecookbook'), assigns(:project)
  end
  
  def test_private_subprojects_hidden
    get :show, :id => 'ecookbook'
    assert_response :success
    assert_template 'show'
    assert_no_tag :tag => 'a', :content => /Private child/
  end

  def test_private_subprojects_visible
    @request.session[:user_id] = 2 # manager who is a member of the private subproject
    get :show, :id => 'ecookbook'
    assert_response :success
    assert_template 'show'
    assert_tag :tag => 'a', :content => /Private child/
  end
  
  def test_settings_routing
    assert_routing(
      {:method => :get, :path => '/projects/4223/settings'},
      :controller => 'projects', :action => 'settings', :id => '4223'
    )
    assert_routing(
      {:method => :get, :path => '/projects/4223/settings/members'},
      :controller => 'projects', :action => 'settings', :id => '4223', :tab => 'members'
    )
  end
  
  def test_settings
    @request.session[:user_id] = 2 # manager
    get :settings, :id => 1
    assert_response :success
    assert_template 'settings'
  end
  
  def test_edit
    @request.session[:user_id] = 2 # manager
    post :edit, :id => 1, :project => {:name => 'Test changed name',
                                       :issue_custom_field_ids => ['']}
    assert_redirected_to 'projects/ecookbook/settings'
    project = Project.find(1)
    assert_equal 'Test changed name', project.name
  end
  
  def test_add_version_routing
    assert_routing(
      {:method => :get, :path => 'projects/64/versions/new'},
      :controller => 'projects', :action => 'add_version', :id => '64'
    )
    assert_routing(
    #TODO: use PUT
      {:method => :post, :path => 'projects/64/versions/new'},
      :controller => 'projects', :action => 'add_version', :id => '64'
    )
  end
  
  def test_add_version
    @request.session[:user_id] = 2 # manager
    assert_difference 'Version.count' do
      post :add_version, :id => '1', :version => {:name => 'test_add_version'}
    end
    assert_redirected_to '/projects/ecookbook/settings/versions'
    version = Version.find_by_name('test_add_version')
    assert_not_nil version
    assert_equal 1, version.project_id
  end
  
  def test_add_version_from_issue_form
    @request.session[:user_id] = 2 # manager
    assert_difference 'Version.count' do
      xhr :post, :add_version, :id => '1', :version => {:name => 'test_add_version_from_issue_form'}
    end
    assert_response :success
    assert_select_rjs :replace, 'issue_fixed_version_id'
    version = Version.find_by_name('test_add_version_from_issue_form')
    assert_not_nil version
    assert_equal 1, version.project_id
  end
  
  def test_add_issue_category_routing
    assert_routing(
      {:method => :get, :path => 'projects/test/categories/new'},
      :controller => 'projects', :action => 'add_issue_category', :id => 'test'
    )
    assert_routing(
    #TODO: use PUT and update form
      {:method => :post, :path => 'projects/64/categories/new'},
      :controller => 'projects', :action => 'add_issue_category', :id => '64'
    )
  end
  
  def test_destroy_routing
    assert_routing(
      {:method => :get, :path => '/projects/567/destroy'},
      :controller => 'projects', :action => 'destroy', :id => '567'
    )
    assert_routing(
    #TODO: use DELETE and update form
      {:method => :post, :path => 'projects/64/destroy'},
      :controller => 'projects', :action => 'destroy', :id => '64'
    )
  end
  
  def test_get_destroy
    @request.session[:user_id] = 1 # admin
    get :destroy, :id => 1
    assert_response :success
    assert_template 'destroy'
    assert_not_nil Project.find_by_id(1)
  end

  def test_post_destroy
    @request.session[:user_id] = 1 # admin
    post :destroy, :id => 1, :confirm => 1
    assert_redirected_to 'admin/projects'
    assert_nil Project.find_by_id(1)
  end
  
  def test_add_file
    set_tmp_attachments_directory
    @request.session[:user_id] = 2
    Setting.notified_events = ['file_added']
    ActionMailer::Base.deliveries.clear
    
    assert_difference 'Attachment.count' do
      post :add_file, :id => 1, :version_id => '',
           :attachments => {'1' => {'file' => uploaded_test_file('testfile.txt', 'text/plain')}}
    end
    assert_redirected_to 'projects/ecookbook/files'
    a = Attachment.find(:first, :order => 'created_at DESC')
    assert_equal 'testfile.txt', a.filename
    assert_equal Project.find(1), a.container

    mail = ActionMailer::Base.deliveries.last
    assert_kind_of TMail::Mail, mail
    assert_equal "[eCookbook] New file", mail.subject
    assert mail.body.include?('testfile.txt')
  end
  
  def test_add_file_routing
    assert_routing(
      {:method => :get, :path => '/projects/33/files/new'},
      :controller => 'projects', :action => 'add_file', :id => '33'
    )
    assert_routing(
      {:method => :post, :path => '/projects/33/files/new'},
      :controller => 'projects', :action => 'add_file', :id => '33'
    )
  end
  
  def test_add_version_file
    set_tmp_attachments_directory
    @request.session[:user_id] = 2
    Setting.notified_events = ['file_added']
    
    assert_difference 'Attachment.count' do
      post :add_file, :id => 1, :version_id => '2',
           :attachments => {'1' => {'file' => uploaded_test_file('testfile.txt', 'text/plain')}}
    end
    assert_redirected_to 'projects/ecookbook/files'
    a = Attachment.find(:first, :order => 'created_at DESC')
    assert_equal 'testfile.txt', a.filename
    assert_equal Version.find(2), a.container
  end
  
  def test_list_files
    get :list_files, :id => 1
    assert_response :success
    assert_template 'list_files'
    assert_not_nil assigns(:containers)
    
    # file attached to the project
    assert_tag :a, :content => 'project_file.zip',
                   :attributes => { :href => '/attachments/download/8/project_file.zip' }
    
    # file attached to a project's version
    assert_tag :a, :content => 'version_file.zip',
                   :attributes => { :href => '/attachments/download/9/version_file.zip' }
  end

  def test_list_files_routing
    assert_routing(
      {:method => :get, :path => '/projects/33/files'},
      :controller => 'projects', :action => 'list_files', :id => '33'
    )
  end

  def test_roadmap_routing
    assert_routing(
      {:method => :get, :path => 'projects/33/roadmap'},
      :controller => 'projects', :action => 'roadmap', :id => '33'
    )
  end
  
  def test_roadmap
    get :roadmap, :id => 1
    assert_response :success
    assert_template 'roadmap'
    assert_not_nil assigns(:versions)
    # Version with no date set appears
    assert assigns(:versions).include?(Version.find(3))
    # Completed version doesn't appear
    assert !assigns(:versions).include?(Version.find(1))
  end
  
  def test_roadmap_with_completed_versions
    get :roadmap, :id => 1, :completed => 1
    assert_response :success
    assert_template 'roadmap'
    assert_not_nil assigns(:versions)
    # Version with no date set appears
    assert assigns(:versions).include?(Version.find(3))
    # Completed version appears
    assert assigns(:versions).include?(Version.find(1))
  end

  def test_roadmap_showing_subprojects_versions
    get :roadmap, :id => 1, :with_subprojects => 1
    assert_response :success
    assert_template 'roadmap'
    assert_not_nil assigns(:versions)
    # Version on subproject appears
    assert assigns(:versions).include?(Version.find(4))
  end
  
  def test_project_activity_routing
    assert_routing(
      {:method => :get, :path => '/projects/1/activity'},
       :controller => 'projects', :action => 'activity', :id => '1'
    )
  end
  
  def test_project_activity_atom_routing
    assert_routing(
      {:method => :get, :path => '/projects/1/activity.atom'},
       :controller => 'projects', :action => 'activity', :id => '1', :format => 'atom'
    )    
  end
  
  def test_project_activity
    get :activity, :id => 1, :with_subprojects => 0
    assert_response :success
    assert_template 'activity'
    assert_not_nil assigns(:events_by_day)
    
    assert_tag :tag => "h3", 
               :content => /#{2.days.ago.to_date.day}/,
               :sibling => { :tag => "dl",
                 :child => { :tag => "dt",
                   :attributes => { :class => /issue-edit/ },
                   :child => { :tag => "a",
                     :content => /(#{IssueStatus.find(2).name})/,
                   }
                 }
               }
  end
  
  def test_previous_project_activity
    get :activity, :id => 1, :from => 3.days.ago.to_date
    assert_response :success
    assert_template 'activity'
    assert_not_nil assigns(:events_by_day)
               
    assert_tag :tag => "h3", 
               :content => /#{3.day.ago.to_date.day}/,
               :sibling => { :tag => "dl",
                 :child => { :tag => "dt",
                   :attributes => { :class => /issue/ },
                   :child => { :tag => "a",
                     :content => /#{Issue.find(1).subject}/,
                   }
                 }
               }
  end
  
  def test_global_activity_routing
    assert_routing({:method => :get, :path => '/activity'}, :controller => 'projects', :action => 'activity', :id => nil)
  end
  
  def test_global_activity
    get :activity
    assert_response :success
    assert_template 'activity'
    assert_not_nil assigns(:events_by_day)
    
    assert_tag :tag => "h3", 
               :content => /#{5.day.ago.to_date.day}/,
               :sibling => { :tag => "dl",
                 :child => { :tag => "dt",
                   :attributes => { :class => /issue/ },
                   :child => { :tag => "a",
                     :content => /#{Issue.find(5).subject}/,
                   }
                 }
               }
  end
  
  def test_user_activity
    get :activity, :user_id => 2
    assert_response :success
    assert_template 'activity'
    assert_not_nil assigns(:events_by_day)
    
    assert_tag :tag => "h3", 
               :content => /#{3.day.ago.to_date.day}/,
               :sibling => { :tag => "dl",
                 :child => { :tag => "dt",
                   :attributes => { :class => /issue/ },
                   :child => { :tag => "a",
                     :content => /#{Issue.find(1).subject}/,
                   }
                 }
               }
  end
  
  def test_global_activity_atom_routing
    assert_routing({:method => :get, :path => '/activity.atom'}, :controller => 'projects', :action => 'activity', :id => nil, :format => 'atom')
  end
  
  def test_activity_atom_feed
    get :activity, :format => 'atom'
    assert_response :success
    assert_template 'common/feed.atom.rxml'
  end
  
  def test_archive_routing
    assert_routing(
    #TODO: use PUT to project path and modify form
      {:method => :post, :path => 'projects/64/archive'},
      :controller => 'projects', :action => 'archive', :id => '64'
    )
  end
  
  def test_archive
    @request.session[:user_id] = 1 # admin
    post :archive, :id => 1
    assert_redirected_to 'admin/projects'
    assert !Project.find(1).active?
  end
  
  def test_unarchive_routing
    assert_routing(
    #TODO: use PUT to project path and modify form
      {:method => :post, :path => '/projects/567/unarchive'},
      :controller => 'projects', :action => 'unarchive', :id => '567'
    )
  end
  
  def test_unarchive
    @request.session[:user_id] = 1 # admin
    Project.find(1).archive
    post :unarchive, :id => 1
    assert_redirected_to 'admin/projects'
    assert Project.find(1).active?
  end
  
  def test_project_breadcrumbs_should_be_limited_to_3_ancestors
    CustomField.delete_all
    parent = nil
    6.times do |i|
      p = Project.create!(:name => "Breadcrumbs #{i}", :identifier => "breadcrumbs-#{i}")
      p.set_parent!(parent)
      get :show, :id => p
      assert_tag :h1, :parent => { :attributes => {:id => 'header'}},
                      :children => { :count => [i, 3].min,
                                     :only => { :tag => 'a' } }
                                     
      parent = p
    end
  end

  def test_copy_with_project
    @request.session[:user_id] = 1 # admin
    get :copy, :id => 1
    assert_response :success
    assert_template 'copy'
    assert assigns(:project)
    assert_equal Project.find(1).description, assigns(:project).description
    assert_nil assigns(:project).id
  end

  def test_copy_without_project
    @request.session[:user_id] = 1 # admin
    get :copy
    assert_response :redirect
    assert_redirected_to :controller => 'admin', :action => 'projects'
  end

  def test_jump_should_redirect_to_active_tab
    get :show, :id => 1, :jump => 'issues'
    assert_redirected_to 'projects/ecookbook/issues'
  end
  
  def test_jump_should_not_redirect_to_inactive_tab
    get :show, :id => 3, :jump => 'documents'
    assert_response :success
    assert_template 'show'
  end
  
  def test_jump_should_not_redirect_to_unknown_tab
    get :show, :id => 3, :jump => 'foobar'
    assert_response :success
    assert_template 'show'
  end


  # A hook that is manually registered later
  class ProjectBasedTemplate < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context)
      # Adds a project stylesheet
      stylesheet_link_tag(context[:project].identifier) if context[:project]
    end
  end
  # Don't use this hook now
  Redmine::Hook.clear_listeners
  
  def test_hook_response
    Redmine::Hook.add_listener(ProjectBasedTemplate)
    get :show, :id => 1
    assert_tag :tag => 'link', :attributes => {:href => '/stylesheets/ecookbook.css'},
                               :parent => {:tag => 'head'}
    
    Redmine::Hook.clear_listeners
  end
end
