class PostsController < ApplicationController
  before_action :set_post, only: %i[ show edit update destroy ]

  # GET /posts, /posts.json or /posts.csv
  def index
    respond_to do |format|
      format.html { @posts = decorate(paginate(Post.published.recent)) }
      format.json { @posts = Post.published.recent.limit(50).to_a }
      format.csv do
        posts = decorate(Post.published.recent.limit(100).to_a)
        send_data PostsExport.new(posts).to_csv, filename: "posts-#{Date.current.iso8601}.csv", type: :csv
      end
    end
  end

  # GET /posts/1 or /posts/1.json
  def show
    @comments = Comment.where(post_id: @post.id).order(:id).to_a
    @comment = Comment.new
    @ratings = Rating.new(@comments.filter_map(&:rating))
    @related = @post.related
    @previous, @next = @post.previous, @post.next
    decorate([ @post ])
    record_view(@post.id)
  end

  # GET /posts/new
  def new
    @post = Post.new
  end

  # GET /posts/1/edit
  def edit
  end

  # POST /posts or /posts.json
  def create
    @post = Post.new(post_params)

    respond_to do |format|
      if @post.save
        format.html { redirect_to @post, notice: "Post was successfully created." }
        format.json { render :show, status: :created, location: @post }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @post.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /posts/1 or /posts/1.json
  def update
    respond_to do |format|
      if @post.update(post_params)
        format.html { redirect_to @post, notice: "Post was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @post }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @post.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /posts/1 or /posts/1.json
  def destroy
    @post.destroy!

    respond_to do |format|
      format.html { redirect_to posts_path, notice: "Post was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_post
      @post = Post.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def post_params
      params.expect(post: [ :title, :body ])
    end
end
