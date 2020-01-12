library(shiny)
library(shinyjs) # for the cookie storing stuff
library(httr)
library(rtweet)
library(future)
library(furrr)

source("twitter.R")

future::plan(future::multiprocess(workers=as.integer(Sys.getenv("FUTURE_WORKERS","4"))))

keys <- jsonlite::read_json("config.json")

hostname <- Sys.getenv("APP_HOSTNAME","")

if_hostname <- function(x){
  if(nchar(trimws(hostname))>0){
    x
  } else {
    NULL
  }
}

# cache ---------------------------------------------

credential_cache <- 
  memoryCache(max_size = as.integer(Sys.getenv("APP_MEMORY_CREDENTIALS","32")) * 1024^2, 
              missing = NULL)

user_tweet_info_cache <-
  memoryCache(max_size = as.integer(Sys.getenv("APP_MEMORY_USER_TWEET_INFO","128")) * 1024^2, 
              max_age = 86400, 
              missing = NULL)

get_user_tweet_info_cache <- function(usernames, token){
  
  user_tweet_info_from_cache <- map(usernames, user_tweet_info_cache$get)
  user_tweet_info_from_pull <- 
    future_pmap(list(usernames, user_tweet_info_from_cache), function(username, user_tweet_info){
      if(is.null(user_tweet_info)){
        get_user_tweet_info(username, token)
      } else {
        NULL
      }
      })
  
  results <- pmap(list(usernames, user_tweet_info_from_cache, user_tweet_info_from_pull), function(username, cache,pull){
    if(is.null(cache) && !is.null(pull)){
      user_tweet_info_cache$set(username, pull)
      pull
    } else if(!is.null(cache)){
      cache
    } else {
      NULL
    }
  })
  results
}

# helper functions ----------------------------


# this is a modification of Michael's code to make the signature for authenticating twitter
# API requests. It's pulled from tokens.R in the rtweet package
oauth_sig <- function(url, method,
                      token = NULL,
                      token_secret = NULL,
                      private_key = NULL, ...) {
  httr::oauth_header(httr::oauth_signature(url, method, app, token,
                                           token_secret, private_key, other_params = list(...)))
}

# This function creates a URL for users to click to authenticate.
# You should use it to show a URL when users haven't authenticated yet.
# the callback_url HAS to be in the app configuration on the developer portal,
# and it needs to have the right http/https protocol.
# for testing in RSTudio I found it best to user 127.0.0.1 and have shiny use port 80
get_authorization_url <- function(app, callback_url, permission=NULL){
  private_key <- NULL
  response <- httr::POST("https://api.twitter.com/oauth/request_token", 
                         oauth_sig("https://api.twitter.com/oauth/request_token",
                                   "POST", private_key = NULL, oauth_callback = callback_url))
  httr::stop_for_status(response)
  params <- httr::content(response, type = "application/x-www-form-urlencoded")
  authorize_url <- httr::modify_url("https://api.twitter.com/oauth/authenticate",
                                    query = list(oauth_token = params$oauth_token, permission = permission))
  authorize_url
  
}

# Once a user authenticates them, Twitter will pass them back to the callback
# url in the authentication one, with the results of the authentication in the query
# of the callback url. This function takes the information from the query
# and does the final conversion to get it into the useful format
get_access_token <- function(app, oauth_token, oauth_verifier){
  url <- paste0("https://api.twitter.com/oauth/access_token?oauth_token=",
                oauth_token,"&oauth_verifier=",oauth_verifier)
  response <- httr::POST(url, 
                         oauth_sig(url,
                                   "POST",
                                   private_key = NULL))
  if(response$status_code == 200L){
    results <- content(response,type="text", encoding="UTF-8")
    results <- strsplit(results,"&")[[1]]
    results <- lapply(results, function(x) strsplit(x,"=")[[1]])
    results <- lapply(results, function(x) setNames(list(x[2]),x[1]))
    results <- do.call(c, results)
    
    results[["screen_name"]] <- NULL # since storing that might be creepy
    results[["user_id"]] <- NULL     # since storing that might be creepy
    
    results
  } else {
    NULL
  }
}

# this code is to handle the fact that Shiny (frustratingly) does not have built in cookie
# manipulation functions. With this code from Calli Gross (https://calligross.de/post/using-cookie-based-authentication-with-shiny/)
# it's now simple to do so!
# Notice that the "expires: 90" means the cookies expire after 90 days.

jsCode <- '
  shinyjs.getcookie = function(params) {
    var cookie = Cookies.get("id");
    if (typeof cookie !== "undefined") {
      Shiny.onInputChange("jscookie", cookie);
    } else {
      var cookie = "";
      Shiny.onInputChange("jscookie", cookie);
    }
  }
  shinyjs.setcookie = function(params) {
    Cookies.set("id", escape(params), { expires: 90 });  
    Shiny.onInputChange("jscookie", params);
  }
  shinyjs.rmcookie = function(params) {
    Cookies.remove("id");
    Shiny.onInputChange("jscookie", "");
  }
'
# The app we'll be using. I didn't give it a name since it doesn't seem to matter
app <- oauth_app(
  app = "",
  key = keys$consumer_key,
  secret = keys$consumer_secret
)


ui <- div(
  tags$head(
    tags$title("Tweet mashup!"),
    tags$link(rel="shortcut icon", href="favicon.ico", type="image/x-icon"),
    tags$meta(name="viewport", content="width=device-width, initial-scale=1, maximum-scale=1"),
    tags$meta(`http-equiv`="x-ua-compatible", content="ie=edge"),
    tags$meta(name="description", content = "Combine two Twitter accounts into one funny tweet!"),
    tags$meta(property="og:title",content="Tweet mashup!"),
    tags$meta(property="og:description", content="Combine two Twitter accounts into one funny tweet!"),
    tags$meta(property="og:type",content="website"),
    if_hostname(tags$meta(property="og:url", content=hostname)),
    if_hostname(tags$meta(property="og:image", content=paste0(hostname,"/open_graph_image.png"))),
    if_hostname(tags$meta(property="og:image:width", content="1200")),
    if_hostname(tags$meta(property="og:image:height", content="630")),
    tags$script(src = "js/js.cookie.min.js"),
    tags$link(rel="stylesheet",
              href="css/bootstrap.min.css"),
    tags$link(rel="stylesheet",
              href="css/bootstrap-theme.min.css"),
    tags$link(rel="stylesheet",
              href="https://maxcdn.bootstrapcdn.com/font-awesome/4.5.0/css/font-awesome.min.css"),
    tags$link(rel = "stylesheet",
              type = "text/css",
              href = "site.css"),
    tags$script(src="js/bootstrap.min.js")
    
  ),
  useShinyjs(),
  extendShinyjs(text = jsCode),
  
  div(class="navbar navbar-static-top hidden-xs",role="navigation",
      div(class="container",
          tags$ul(class = "nav navbar-nav navbar-right",
                  tags$li(
                    p(class="navbar-text navbar-right",
                      HTML("Made by <a href=\"https://nolisllc.com\" target=\"_blank\">Nolis, LLC</a> with help from <a href=\"http://jesseddy.com\" class=\"navbar-link\" target=\"_blank\">Jess Eddy</a>")
                    )
                  )
          )
      )
  ),
  
  tags$section(class="bg-primary",
               div(class="container text-center",
                   h1("Tweet mashup!"),
                   h3("Combine tweets from two Twitter accounts for one awesome tweet!"))),
  
  div(class="container",
      uiOutput("try_it", class="try-it-input"), # this will either show a link to authenticate or some tweets
      uiOutput("generated_tweet_title"),
      #withSpinner(uiOutput("generated_tweet"), color="#f26d7e", type=8, proxy.height="80px")
      uiOutput("generated_tweet")
  )
)


server <- function(input, output, session) {
  
  # store the user id that will span sessions. It's a UUID stored in the user cookies
  user_id <- reactive({
    js$getcookie()
    
    # If the cookie loading but it's empty that means we have a new user 
    # and need to give them an id
    if (!is.null(input$jscookie) && 
        is.character(input$jscookie) &&
        nchar(trimws(input$jscookie)) == 0) {
      user_id <- paste0(sample(c(letters,0:9), 32, replace=TRUE),collapse="")
      js$setcookie(user_id)
    } else {
      user_id <- input$jscookie
    }
    user_id
  })
  
  # this will be NULL if the user hasn't logged in yet, otherwise 
  # it will have the valid twitter token for user
  access_token <- reactive({
    if(is.null(user_id())){ # if we don't even have a UUID yet then there are no keys
      access_token <- NULL
    } else {
      
      # check if we have saved the keys in the cache
      access_token <- credential_cache$get(user_id())
      
      if(is.null(access_token)){
        # is the user is coming in from having just authenticated? 
        # if yes save the tokens, if not then no keys to user
        query <- getQueryString(session)
        if(!is.null(query) 
           && !is.null(query$oauth_token) 
           && !is.null(query$oauth_verifier)){ 
          access_token <- get_access_token(app, query$oauth_token, query$oauth_verifier)
          if(!is.null(access_token)){
            credential_cache$set(user_id(), access_token)
          }
        }
      }
    }
    # turn the information from the file into a valid token object
    if(!is.null(access_token)){
      create_token(app="", 
                   keys$consumer_key, 
                   keys$consumer_secret, 
                   access_token = access_token$oauth_token, 
                   access_secret = access_token$oauth_token_secret)
    }
  })
  
  username_1 <- reactive({
    original <- input$username_1
    username <- NULL
    if(!is.null(original)){
      fixed_username <- fix_username(original)
      if(nchar(fixed_username) > 0){
        username <- fixed_username
      }
    }
    username
  })
  
  username_2 <- reactive({
    original <- input$username_2
    username <- NULL
    if(!is.null(original)){
      fixed_username <- fix_username(original)
      if(nchar(fixed_username) > 0){
        username <- fixed_username
      }
    }
    username
  })
  
  user_tweet_info <- reactive({
    input$generate
    username_1 <- isolate({username_1()})
    username_2 <- isolate({username_2()})
    access_token <- isolate({access_token()})
    if(!is.null(username_1) && !is.null(username_2)){
      user_tweet_info <- get_user_tweet_info_cache(c(username_1, username_2), access_token)
      setNames(user_tweet_info, c("username_1", "username_2"))
    } else {
      NULL
    }
  })
  
  generated_tweet <- reactive({
    input$generate
    user_tweet_info <- isolate({user_tweet_info()})
    if(!is.null(user_tweet_info) && 
       !is.null(user_tweet_info$username_1) && 
       !is.null(user_tweet_info$username_2)){
      make_combined_tweet(user_tweet_info$username_1, user_tweet_info$username_2)
    } else {
      NULL
    }
  })
  
  callback_url <- reactive({paste0(session$clientData$url_protocol,"//",session$clientData$url_hostname)})
  
  # either show the authentication URL or a few tweets
  output$try_it <- renderUI({
    if(is.null(access_token())){
      if(is.null(user_id())){
        return(NULL)
      }
      url <- get_authorization_url(app, callback_url = callback_url())
      tags$form(
        div(class="form-group row vertical-align",
            div(class="col-sm-5 col-xs-12",
                div(class="input-group",
                    span(class="input-group-addon","@"),
                    tags$input(type="text",class="form-control",  id="username_1", disabled=NA)
                )),
            div(class="col-sm-1 hidden-xs",h1("&", class="ampersand text-center")),
            div(class="col-sm-5 col-xs-12",
                div(class="input-group",
                    span(class="input-group-addon","@"),
                    tags$input(type="text",class="form-control", id="username_2", disabled=NA)
                )),
            div(class="col-sm-1 col-xs-12 text-center",a(class="btn twitter-button", href = url, tags$i(class="fa fa-twitter"), "Authorize!")))
      )
    } else {
      tags$form(
        div(class="form-group row vertical-align",
            div(class="col-sm-5 col-xs-12",
                div(class="input-group",
                    span(class="input-group-addon","@"),
                    tags$input(type="text",class="form-control",  id="username_1")
                )),
            div(class="col-sm-1 hidden-xs",h1("&", class="ampersand text-center")),
            div(class="col-sm-5 col-xs-12",
                div(class="input-group",
                    span(class="input-group-addon","@"),
                    tags$input(type="text",class="form-control", id="username_2")
                )),
            div(class="col-sm-1 col-xs-12 text-center",actionButton("generate","Go!", class="btn btn-primary")))
      )
    }
    
  })
  
  output$generated_tweet_title <- renderUI({
    user_tweet_info <- user_tweet_info()
    
    if(!is.null(user_tweet_info)){
      user_info_1 <- user_tweet_info$username_1$user_info
      user_info_2 <- user_tweet_info$username_2$user_info
      div(class="output-ui container",
          div(class="row",
              div(class="col-sm-4 left-name hidden-xs",
                  h4(user_info_1$name),
                  h6(tags$em(paste0("@",user_info_1$screen_name)))
              ),
              div(class="overlapping-images col-sm-4",
                  img(src=user_info_1$image_url, class="img-circle img-left", width = "128", height ="128"),
                  img(src=user_info_2$image_url, class="img-circle img-right", width = "128", height ="128")
              ),
              div(class="col-sm-4 right-name hidden-xs",
                  h4(user_info_2$name),
                  h6(tags$em(paste0("@",user_info_2$screen_name)))
              )
          ),
          div(class="row text-center",
              h4(HTML("Tweet mashup by <a href=\"https://nolisllc.com\" target=\"_blank\">Nolis, LLC</a>"))
          )
      )
    } else {
      NULL
    }
  })
  
  output$generated_tweet <- renderUI({
    if(is.null(generated_tweet())){
      generated_tweet <- ""
    } else {
      generated_tweet <- generated_tweet()
    }
    div(class="row", p(class="tweet-text text-center", generated_tweet))
  })
}

# make sure you use port 80 or whatever you put in the twitter developer portal
# in RStudio if you hit "Run App" it ignore the port, so watch out!
shinyApp(ui = ui, server = server, options=list(port=80L, launch.browser=FALSE))

