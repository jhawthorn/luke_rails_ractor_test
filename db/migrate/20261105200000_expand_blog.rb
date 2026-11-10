class ExpandBlog < ActiveRecord::Migration[8.2]
  def change
    create_table :authors do |t|
      t.string :name, null: false
      t.string :handle, null: false, index: { unique: true }
      t.string :email, null: false
      t.text :bio
      t.date :joined_on
      t.timestamps
    end

    create_table :tags do |t|
      t.string :name, null: false
      t.string :slug, null: false, index: { unique: true }
      t.timestamps
    end

    create_table :taggings do |t|
      t.references :post, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.index %i[ tag_id post_id ], unique: true
    end

    create_table :page_views do |t|
      t.integer :post_id, index: true
      t.string :path, null: false
      t.string :user_agent
      t.string :remote_ip
      t.integer :duration_us
      t.datetime :created_at, null: false, index: true
    end

    change_table :posts do |t|
      t.references :author, foreign_key: true
      t.string :slug, index: { unique: true }
      t.datetime :published_at, index: true
      t.integer :views_count, default: 0, null: false
      t.integer :words_count, default: 0, null: false
      # Front-matter style settings, stored as JSON text and parsed per request.
      t.text :metadata
    end

    add_column :comments, :rating, :integer
  end
end
