defmodule ChangelogWeb.Router do
  use ChangelogWeb, :router
  use Plug.ErrorHandler

  alias ChangelogWeb.Plug

  if Mix.env == :dev do
    forward "/sent_emails", Bamboo.EmailPreviewPlug
  end

  pipeline :browser do
    plug :accepts, ["html", "xml"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Plug.Auth, repo: Changelog.Repo
    plug PlugEtsCache.Plug
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug PlugEtsCache.Plug
  end

  pipeline :admin do
    plug :put_layout, {ChangelogWeb.LayoutView, :admin}
    plug Plug.RequireAdmin
  end

  pipeline :public do
    plug Plug.LoadPodcasts
    plug Plug.Turbolinks
  end

  scope "/auth", ChangelogWeb do
    pipe_through [:browser, :public]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback
  end

  scope "/admin", ChangelogWeb.Admin, as: :admin do
    pipe_through [:browser, :admin]

    get "/", PageController, :index
    get "/search", SearchController, :all
    get "/search/:type", SearchController, :one

    resources "/benefits", BenefitController, except: [:show]
    resources "/topics", TopicController, except: [:show]

    get "/news", NewsItemController, :index
    resources "/news/items", NewsItemController, except: [:show]
    post "/news/items/:id/move", NewsItemController, :move, as: :news_item
    resources "/news/sources", NewsSourceController, except: [:show]
    resources "/news/sponsorships", NewsSponsorshipController, except: [:show]
    get "/news/sponsorships/schedule", NewsSponsorshipController, :schedule
    resources "/news/issues", NewsIssueController, except: [:show]
    post "/news/issues/:id/publish", NewsIssueController, :publish, as: :news_issue
    post "/news/issues/:id/unpublish", NewsIssueController, :unpublish, as: :news_issue

    resources "/people", PersonController, except: [:show]
    resources "/podcasts", PodcastController do
      resources "/episodes", EpisodeController
      post "/episodes/:id/publish", EpisodeController, :publish, as: :episode
      post "/episodes/:id/unpublish", EpisodeController, :unpublish, as: :episode
      post "/episodes/:id/transcript", EpisodeController, :transcript, as: :episode
    end
    resources "/posts", PostController, except: [:show]
    resources "/sponsors", SponsorController
  end

  scope "/api", ChangelogWeb, as: :api do
    pipe_through [:api]

    get "/oembed", ApiController, :oembed
  end

  scope "/github", ChangelogWeb do
    pipe_through [:api]

    post "/event", GithubController, :event
  end

  scope "/slack", ChangelogWeb do
    pipe_through [:api]

    get "/countdown/:slug", SlackController, :countdown
    post "/countdown/:slug", SlackController, :countdown
    post "/event", SlackController, :event
  end

  scope "/", ChangelogWeb do
    pipe_through [:browser, :public]

    #feeds
    get "/feed", FeedController, :all
    get "/feed/titles", FeedController, :all_titles
    get "/posts/feed", FeedController, :posts
    get "/sitemap.xml", FeedController, :sitemap
    get "/:slug/feed", FeedController, :podcast

    # people and auth
    resources "/people", PersonController, only: [:new, :create]
    resources "/~", HomeController, only: [:show, :edit, :update], singleton: true
    post "/~/slack", HomeController, :slack
    post "/~/subscribe/:id", HomeController, :subscribe
    post "/~/unsubscribe/:id", HomeController, :unsubscribe

    get "/community", PageController, :community
    get "/join", PageController, :join
    get "/in", AuthController, :new, as: :sign_in
    post "/in", AuthController, :new, as: :sign_in
    get "/in/:token", AuthController, :create, as: :sign_in
    get "/out", AuthController, :delete, as: :sign_out

    resources "/benefits", BenefitController, only: [:index]
    resources "/posts", PostController, only: [:index, :show]
    get "/posts/:id/preview", PostController, :preview, as: :post
    get "/news/issues/:id", NewsIssueController, :show, as: :news_issue
    get "/news/issues/:id/preview", NewsIssueController, :preview, as: :news_issue

    get "/live", LiveController, :index
    get "/live/status", LiveController, :status
    get "/search", SearchController, :search

    # static pages
    get "/", PageController, :home
    get "/about", PageController, :about
    get "/coc", PageController, :coc
    get "/contact", PageController, :contact
    get "/films", PageController, :films
    get "/films/gophercon-2015", PageController, :films_gophercon_2015
    get "/films/gophercon-2016", PageController, :films_gophercon_2016
    get "/guest", PageController, :guest
    get "/guest/:slug", PageController, :guest
    get "/styleguide", PageController, :styleguide
    get "/subscribe", PageController, :subscribe
    get "/partnership", PageController, :partnership
    get "/sponsor", PageController, :sponsor
    get "/store", PageController, :store
    get "/team", PageController, :team
    get "/privacy", PageController, :privacy
    get "/terms", PageController, :terms

    get "/nightly", PageController, :nightly
    get "/nightly/confirmed", PageController, :nightly_confirmed
    get "/nightly/unsubscribed", PageController, :nightly_unsubscribed

    get "/weekly", PageController, :weekly
    get "/weekly/archive", PageController, :weekly_archive
    get "/weekly/confirmed", PageController, :weekly_confirmed
    get "/weekly/unsubscribed", PageController, :weekly_unsubscribed

    get "/gotime/confirmed", PageController, :gotime_confirmed
    get "/rfc/confirmed", PageController, :rfc_confirmed

    get "/confirmation-pending", PageController, :confirmation_pending

    get "/podcasts", PodcastController, :index, as: :podcast
    get "/:slug", PodcastController, :show, as: :podcast
    get "/:slug/archive", PodcastController, :archive, as: :podcast

    get "/:podcast/:slug", EpisodeController, :show, as: :episode
    get "/:podcast/:slug/embed", EpisodeController, :embed, as: :episode
    get "/:podcast/:slug/preview", EpisodeController, :preview, as: :episode
    get "/:podcast/:slug/play", EpisodeController, :play, as: :episode
    get "/:podcast/:slug/share", EpisodeController, :share, as: :episode
  end

  defp handle_errors(_conn, %{reason: %Phoenix.Router.NoRouteError{}}), do: true
  defp handle_errors(conn, %{kind: kind, reason: reason, stack: stacktrace}) do
    headers = Enum.into(conn.req_headers, %{})

    Rollbax.report(kind, reason, stacktrace, %{}, %{
      "request" => %{
        "url" => "#{conn.scheme}://#{conn.host}#{conn.request_path}",
        "user_ip" => Map.get(headers, "x-forwarded-for"),
        "method" => conn.method,
        "headers" => headers,
        "params" => conn.params
      }
    })
  end
end
