# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2026_11_05_200000) do
  create_table "authors", force: :cascade do |t|
    t.string "name", null: false
    t.string "handle", null: false
    t.string "email", null: false
    t.text "bio"
    t.date "joined_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["handle"], name: "index_authors_on_handle", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.integer "post_id", null: false
    t.string "author"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "rating"
    t.index ["post_id"], name: "index_comments_on_post_id"
  end

  create_table "page_views", force: :cascade do |t|
    t.integer "post_id"
    t.string "path", null: false
    t.string "user_agent"
    t.string "remote_ip"
    t.integer "duration_us"
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_page_views_on_created_at"
    t.index ["post_id"], name: "index_page_views_on_post_id"
  end

  create_table "posts", force: :cascade do |t|
    t.string "title"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "comments_count", default: 0, null: false
    t.integer "author_id"
    t.string "slug"
    t.datetime "published_at"
    t.integer "views_count", default: 0, null: false
    t.integer "words_count", default: 0, null: false
    t.text "metadata"
    t.index ["author_id"], name: "index_posts_on_author_id"
    t.index ["published_at"], name: "index_posts_on_published_at"
    t.index ["slug"], name: "index_posts_on_slug", unique: true
  end

  create_table "taggings", force: :cascade do |t|
    t.integer "post_id", null: false
    t.integer "tag_id", null: false
    t.index ["post_id"], name: "index_taggings_on_post_id"
    t.index ["tag_id", "post_id"], name: "index_taggings_on_tag_id_and_post_id", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_tags_on_slug", unique: true
  end

  add_foreign_key "comments", "posts"
  add_foreign_key "posts", "authors"
  add_foreign_key "taggings", "posts"
  add_foreign_key "taggings", "tags"
end
