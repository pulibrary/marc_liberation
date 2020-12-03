Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }
  mount Locations::Engine, at: '/locations'

  resources :dump_files, only: [:show]
  resources :events, only: [:show, :index, :destroy]
  resources :dumps, only: [:show]

  get '/bibliographic', to: 'bibliographic#index', defaults: { format: :txt }
  get '/bibliographic/:bib_id', to: 'bibliographic#bib', defaults: { format: :xml }, as: :show_bib
  get '/bibliographic/:bib_id/holdings', to: 'bibliographic#bib_holdings', defaults: { format: :xml }
  get '/bibliographic/:bib_id/jsonld', to: 'bibliographic#bib_jsonld'
  get '/bibliographic/:bib_id/items', to: 'bibliographic#bib_items', defaults: { format: :json }
  get '/bibliographic/:bib_id/solr', to: 'bibliographic#bib_solr'
  post '/bibliographic', to: 'bibliographic#update'

  get '/holdings', to: 'holdings#index', defaults: { format: :txt }
  get '/holdings/:bib_id/:holding_id', to: 'holdings#holding', defaults: { format: :json, format: :xml }
  get '/holdings/:bib_id/:holding_id/items', to: 'holdings#holding_items', defaults: { format: :json, format: :xml }

  get '/availability', to: 'availability#index', defaults: { format: :json }

  get '/items', to: 'items#index', defaults: { format: :txt }
  get '/items/:item_id', to: 'items#item', defaults: { format: :json }

  get '/barcode', to: 'barcode#index', defaults: { format: :txt }
  get '/barcode/:barcode', to: 'barcode#barcode', defaults: { format: :xml }, as: :show_barcode
  get '/barcode/:barcode/scsb', to: 'barcode#scsb', defaults: { format: :xml }

  get '/codes/:location', to: 'codes#locations', defaults: { format: :json }
  get '/patron/:patron_id', to: 'patron#patron_info', format: false, defaults: { format: :json }, constraints: { patron_id: /[^\/]+/ }
  get '/patron/:patron_id/codes', to: 'patron#patron_codes', format: false, defaults: { format: :json }, constraints: { patron_id: /[^\/]+/ }

  get '/courses', to: 'courses#index', defaults: { format: :json }
  get "/bib_ids", to: 'courses#bibs', defaults: { format: :json }

  get '/hathi/access', to: 'hathi#hathi_access', defaults: { format: :json }

  get "/campus_access", to: 'campus_access#index', defaults: { format: :csv }

  require 'sidekiq/web'
  authenticate :user do
    mount Sidekiq::Web => '/sidekiq'
  end
end
