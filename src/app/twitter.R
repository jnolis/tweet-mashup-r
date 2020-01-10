library(rtweet)
library(purrr)
library(dplyr)

max_tweet_length <- 280

fix_username <- function(username){
  gsub("[^[:alnum:]_]", "", username)
}

get_user_facts <- function(username,token){
  large_image_urls <- function(urls){
    sub("_normal\\.", "_400x400.", urls)
  }
  fix_https <- function(urls){
    sub("^http://","https://", urls)
  }
  
  user <- lookup_users(username,token=token)
  image_url <-  large_image_urls(user$profile_image_url)
  list(name = user$name, 
       screen_name = user$screen_name,
       image_url = image_url
       )
}

get_tweets <- function(username, token, n = 640){
  raw_tweets <- get_timeline(username,n=n, token=token)
  if(nrow(raw_tweets) > 0){
    filtered <- raw_tweets[!raw_tweets$is_retweet & is.na(raw_tweets$reply_to_status_id),c("status_id","text")]
    tweets <- setNames(filtered$text,filtered$status_id)
    
    clean_tweets <- function(tweets){
      tweets <- gsub("\\s+", " ", tweets)
      tweets <- gsub("https?://.*\\b","",tweets)
      tweets <- trimws(tweets)
      tweets
    }
    
    tweets <- clean_tweets(tweets)
  } else {
    tweets <- list()
  }
  tweets
}

make_word_lookup <- function(tweets){
  process_one_word_lookup <- function(word_list, tweet_id){
    word_char_num <- nchar(word_list)
    word_cum_sum <- cumsum(word_char_num) + 0:(length(word_char_num)-1)
    
    characters_before <- word_cum_sum - word_char_num
    characters_after <- sum(word_char_num) - word_cum_sum 
    
    one_word_lookup <- transpose(list(
      word = word_list,
      clean_word = clean_words(word_list),
      chars_before_word = characters_before,
      chars_in_word = word_char_num,
      chars_after_word = characters_after,
      tweet_id = rep(tweet_id, length(word_list))))
    
    one_word_lookup <- one_word_lookup[c(-1,-length(one_word_lookup))] 
    # remove the first and last words because they're dull
    
  }
  
  clean_words <- function(words){
    tolower(gsub("[^[:alpha:]]","",words))
  }
  
  word_lists <- strsplit(tweets," ")
  
  word_lookup <- flatten_dfr(imap(word_lists, process_one_word_lookup))
  word_lookup
}

get_user_tweet_info <- function(username, token){
  username <- fix_username(username)
  user_info <- get_user_facts(username, token)
  tweets <- get_tweets(username, token)
  word_lookup <- make_word_lookup(tweets)
  list(username = username,
       user_info = user_info,
       tweets = tweets,
       word_lookup = word_lookup)
}

make_combined_tweet <- function(user_tweet_info_1, user_tweet_info_2){
  tweets_1 <- user_tweet_info_1$tweets
  tweets_2 <- user_tweet_info_2$tweets
  word_lookup_1 <- user_tweet_info_1$word_lookup
  word_lookup_2 <- user_tweet_info_2$word_lookup
  
  all_splits <- inner_join(rename_at(word_lookup_1,vars(-clean_word), function(x) paste0(x,"_1")),
                      rename_at(word_lookup_2,vars(-clean_word), function(x) paste0(x,"_2")),
                      by="clean_word")
  all_splits <- 
    mutate(all_splits,
           fst_1_valid = chars_before_word_1 + chars_in_word_1 + chars_after_word_2 <= max_tweet_length,
           fst_2_valid = chars_before_word_2 + chars_in_word_2 + chars_after_word_1 <= max_tweet_length)
  split <- sample_n(all_splits, 1, weight = fst_1_valid + fst_2_valid)
  
  if(split$fst_1_valid & split$fst_2_valid){
    fst_1 <- sample(c(F,T),1)
  } else if(split$fst_1_valid){
    fst_1 <- TRUE
  } else {
    fst_1 <- FALSE
  }
  
  if(fst_1){
    fst_half <- substr(tweets_1[[split$tweet_id_1]], 1, with(split,chars_before_word_1 + chars_in_word_1))
    snd_half <- substr(tweets_2[[split$tweet_id_2]], with(split, chars_before_word_2 + chars_in_word_2 + 1), max_tweet_length)
  } else {
    fst_half <- substr(tweets_2[[split$tweet_id_2]], 1, with(split,chars_before_word_2 + chars_in_word_2))
    snd_half <- substr(tweets_1[[split$tweet_id_1]], with(split, chars_before_word_1 + chars_in_word_1 + 1), max_tweet_length)
  }
  
  generated_tweet <- paste0(fst_half, snd_half)
  generated_tweet
}
