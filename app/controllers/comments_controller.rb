class CommentsController < ApplicationController
  before_action :set_post

  # POST /posts/1/comments
  def create
    # Built directly rather than via @post.comments, which isn't Ractor-safe yet.
    @comment = Comment.new(comment_params.merge(post_id: @post.id))

    if @comment.save
      redirect_to @post, notice: "Comment added."
    else
      # Re-render the post page so the form shows the validation errors.
      @comments = Comment.where(post_id: @post.id).order(:id)
      render "posts/show", status: :unprocessable_content
    end
  end

  # DELETE /posts/1/comments/2
  def destroy
    Comment.where(post_id: @post.id).find(params.expect(:id)).destroy!
    redirect_to @post, notice: "Comment removed.", status: :see_other
  end

  private
    def set_post
      @post = Post.find(params.expect(:post_id))
    end

    def comment_params
      params.expect(comment: [ :author, :body ])
    end
end
