# BetterMeans - Work 2.0
# Copyright (C) 2006  Shereef Bishay
#

class IssueStatusesController < ApplicationController
  before_filter :require_admin

  verify :method => :post, :only => [ :destroy, :create, :update, :move ],
         :redirect_to => { :action => :list }
         
  def index
    list
    render :action => 'list' unless request.xhr?
  end

  def list
    @issue_status_pages, @issue_statuses = paginate :issue_statuses, :per_page => 25, :order => "position"
    render :action => "list", :layout => false if request.xhr?
  end

  def new
    @issue_status = IssueStatus.new
  end

  def create
    @issue_status = IssueStatus.new(params[:issue_status])
    if @issue_status.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to :action => 'list'
    else
      render :action => 'new'
    end
  end

  def edit
    @issue_status = IssueStatus.find(params[:id])
  end

  def update
    @issue_status = IssueStatus.find(params[:id])
    if @issue_status.update_attributes(params[:issue_status])
      flash[:notice] = l(:notice_successful_update)
      redirect_to :action => 'list'
    else
      render :action => 'edit'
    end
  end

  def destroy
    IssueStatus.find(params[:id]).destroy
    redirect_to :action => 'list'
  rescue
    flash[:error] = "Unable to delete issue status"
    redirect_to :action => 'list'
  end  	
end
