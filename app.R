#     _____       __                          __
#    |__  /      / /__  ____ _____ ____  ____/ /
#     /_ <______/ / _ \/ __ `/ __ `/ _ \/ __  / 
#   ___/ /_____/ /  __/ /_/ / /_/ /  __/ /_/ /  
#  /____/     /_/\___/\__, /\__, /\___/\__,_/   
#                    /____//____/               
#         RTWEET + 3-LEGGED-AUTH DEMO

# This code demonstrates how to do 3-legged authentication for Twitter
# using the {rtweet} package. Based heavily on code from Michael Kearney and Calli Gross

# To run this you need:
# 1. An app set up in the twitter developer portal
# 2. A config.yml file set up with the API keys like so:
# default:
#   consumer_key: "xxx"
#   consumer_secret: "xxx"
#   access_token: "xxx"
#   access_secret: "xxx"
# 3. The following file saved to a "www" folder in the same folder as this file: https://cdn.jsdelivr.net/npm/js-cookie@2/src/js.cookie.min.js

library(shiny)
library(shinyjs) # for the cookie storing stuff
library(uuid)
library(jsonlite)
library(httr)
library(rtweet)

# this loads the consumer/access keys from a yaml file using the config package.
# You can load them however you want!
keys <- config::get()

# this folder is where the keys will be stored so people can use them without
# having to log in again each time
if (!dir.exists('data/')) {
  dir.create('data')
}

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
  
  results <- content(response,type="text", encoding="UTF-8")
  results <- strsplit(results,"&")[[1]]
  results <- lapply(results, function(x) strsplit(x,"=")[[1]])
  results <- lapply(results, function(x) setNames(list(x[2]),x[1]))
  results <- do.call(c, results)
  
  results[["screen_name"]] <- NULL # since storing that might be creepy
  results[["user_id"]] <- NULL     # since storing that might be creepy
  
  results
}

# this code is to handle the fact that Shiny (frustratingly) does not have built in cookie
# manipulation functions. With this code from Calli Gross (https://calligross.de/post/using-cookie-based-authentication-with-shiny/)
# it's now simple to do so!
# Notice that the "expires: 90" means the cookies expire after 90 days.

addResourcePath("js", "www")
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


ui <- fluidPage(
  tags$head(
    tags$script(src = "js/js.cookie.min.js")
  ),
  useShinyjs(),
  extendShinyjs(text = jsCode),
  verticalLayout(
    uiOutput("main") # this will either show a link to authenticate or some tweets
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
      user_id <- UUIDgenerate()
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
      key_file <- paste0("data/",user_id(),".json")
      
      # check if we have saved the keys to a file
      if(nchar(user_id()) > 0 && file.exists(key_file)){
        access_token <- read_json(key_file) # load from a file if possible
      } else {
        
        # is the user is coming in from having just authenticated? 
        # if yes save the tokens, if not then no keys to user
        query <- getQueryString(session)
        if(!is.null(query) 
           && !is.null(query$oauth_token) 
           && !is.null(query$oauth_verifier)){ 
          access_token <- get_access_token(app, query$oauth_token, query$oauth_verifier)
          write_json(access_token, key_file)
        } else {
          access_token <- NULL
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
  
  # either show the authentication URL or a few tweets
  output$main <- renderUI({
    if(is.null(access_token())){
      url <- get_authorization_url(app, callback_url = "http://127.0.0.1")
      a(href = url, "Click here to authorize this app")
    } else {
      do.call(div,lapply(get_my_timeline(token = access_token())$text[1:3], p))
    }
  })
  
}

# make sure you use port 80 or whatever you put in the twitter developer portal
# in RStudio if you hit "Run App" it ignore the port, so watch out!
shinyApp(ui = ui, server = server, options=list(port=80L))