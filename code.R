library(tidyverse) 
library(lubridate)
library(tidygraph)
library(graphlayouts)
library(igraph)
library(intergraph)
library(ggraph)
library(rtweet)

################################################################################

# IESEG Twitter account scrapping 

################################################################################

# Token authentication 
apikey <- "U92hesGbjePlPKC4p6iLlXeEQ"
apisecret <- "SQ4tLqFAv31wtneoBZoaxB6tOKiFtX2kDayBZMlWYowYZkrWrI"
acctoken <- "1481731378114961416-f5q6OebIwV7e0j5l34FrnK6EdDgat9"
tokensecret <- "cWoer6M1EfPAOoOC3c1PkbMe6D3FX6URoOBCCYVfxEEg0"
token <- create_token(app = "Twitter SNA",
                      consumer_key = apikey,
                      consumer_secret = apisecret,
                      access_token = acctoken,
                      access_secret = tokensecret)
# check the token
get_token()


# gather IESEG data
algo <- lookup_users("IESEG")
# get IESEG followers and its account details
folower <- get_followers("IESEG",n = 500,retryonratelimit = T)
detail_folower <- lookup_users(folower$user_id)
detail_folower <- data.frame(lapply(detail_folower,as.character),
                             stringsAsFactors = F)


# filter active users
active_followers <- detail_folower %>% select(user_id,screen_name,created_at,followers_count,friends_count,favourites_count) %>%
         mutate(created_at = ymd_hms(created_at),
         followers_count = 500,
         friends_count = as.numeric(friends_count),
         favourites_count = as.numeric(favourites_count)) %>%
         filter((followers_count > 100 & followers_count < 5000), friends_count > 100, favourites_count > 10,created_at > "2022-01-01")

dim(active_followers)

fol_n <- function(x){
    x*0.5
}


# Create empty list and name it after their screen name
followers <- vector(mode = 'list', length = length(active_followers$screen_name))
names(followers) <- active_followers$screen_name
# 
for (i in seq_along(active_followers$screen_name)) {
  message("Getting followers for user #", i)
  followers[[i]] <- get_followers(active_followers$screen_name[i], 
                              n = round(fol_n(active_followers$followers_count[i])), 
                              retryonratelimit = TRUE)
  if(i %% 5 == 0){
    message("sleep for 5 minutes")
    Sys.sleep(5*60)
  } 
}

# convert list to dataframe
follwerx <- bind_rows(followers, .id = "screen_name")
active_fol_x <- active_followers %>% select(user_id,screen_name)
# left join to convert screen_name into its user id
follwer_join <- left_join(follwerx, active_fol_x, by="screen_name")
# subset to new dataframe with new column name and delete NA
ieseg_follower <- follwer_join %>% select(user_id.x,user_id.y) %>%
  setNames(c("follower","active_user")) %>% 
  na.omit()
save(ieseg_follower,file="followers.Rda")

following <- function(x){
  x*0.4
}

################################################################################

# Preprocessing 

################################################################################

following_df <- data.frame()
for (i in seq_along(active_followers$screen_name)) {
  message("Getting followers for user #", i)
  kk <- get_friends(active_followers$screen_name[i],
                    n = round(following(active_followers$friends_count[i])),
                    retryonratelimit = TRUE)
  
  following_df <- rbind(following_df,kk)
  
  if(i %% 5 == 0){
    message("sleep for 5 minutes")
    Sys.sleep(5*60)
  } 
}

all_friend <- following_df %>% setNames(c("screen_name","user_id"))
all_friendx <- left_join(all_friend, active_fol_x, by="screen_name")
ieseg_friend <- all_friendx %>% select(user_id.x,user_id.y) %>%
  setNames(c("following","active_user"))
dim(ieseg_friend)

save(ieseg_friend,file="following.Rda")

# collect unique user_id in ieseg_friend df
un_active <- unique(ieseg_friend$active_user) %>% data.frame(stringsAsFactors = F) %>%
  setNames("active_user")


# create empty dataframe
ieseg_mutual <- data.frame()

# loop function to filter the df by selected unique user, then find user that presence in both algo_friend$following and algo_follower$follower column set column name, and store it to algo_mutual df
for (i in seq_along(un_active$active_user)){
  aa <- ieseg_friend %>% filter(active_user == un_active$active_user[i])
  bb <- aa %>% filter(aa$following %in% ieseg_follower$follower) %>%
    setNames(c("mutual","active_user"))
  
  ieseg_mutual <- rbind(ieseg_mutual,bb)
}

un_active <- un_active %>% mutate(mutual = rep("IESEG"))
# swap column oreder
un_active <- un_active[,c(2,1)]
# rbind to ieseg_mutual df
ieseg_mutual <- rbind(ieseg_mutual,un_active)
ieseg_mutual

################################################################################

# Social Network Analysis 

################################################################################

# create nodes data
nodes <- data.frame(V = unique(c(ieseg_mutual$mutual,ieseg_mutual$active_user)),
                    stringsAsFactors = F)
# create edges data
edges <- ieseg_mutual %>% setNames(c("from","to"))

# create graph
tbl <- graph_from_data_frame(d = edges, vertices = nodes, directed = F) %>% as_tbl_graph()

# create communitites
community <- walktrap.community(tbl, steps=2000,modularity=TRUE)

# add communities and centrality analysis to the tbl_graph object
set.seed(123)
network <- tbl %>% 
  mutate(community = as.factor(membership(community)))%>%
  mutate(degree_c = centrality_degree()) %>%
  mutate(betweenness_c = centrality_betweenness(directed = F,normalized = T)) %>%
  mutate(closeness_c = centrality_closeness(normalized = T)) %>%
  mutate(eigen = centrality_eigen(directed = F))

network_df <- as.data.frame(network %>% activate(nodes))
network_df


# take 6 highest user by its centrality
inf_user <- data.frame(
  network_df %>% arrange(-degree_c) %>% select(name) %>% slice(1:6),
  network_df %>% arrange(-betweenness_c) %>% select(name) %>% slice(1:6),
  network_df %>% arrange(-closeness_c) %>% select(name) %>% slice(1:6),
  network_df %>% arrange(-eigen) %>% select(name) %>% slice(1:6)
) %>% setNames(c("degree","betweenness","closeness","eigen"))
inf_user

influencial_account <- lookup_users("700418206138245120")
influencial_account$screen_name


# plot the network 

IESEG_Net <- network %>%
  top_n(1000,degree_c) %>%
  mutate(node_size = ifelse(degree_c >= 100,degree_c*5,degree_c*2)) %>%
  mutate(node_label = ifelse(degree_c >= 308,lookup_users("700418206138245120")$screen_name,""))%>%
  ggraph(layout = "stress") +
  geom_edge_fan(alpha = 0.05) +
  geom_node_point(aes(color=as.factor(community),size = node_size)) +
  geom_node_label(aes(label = node_label),repel = T,show.legend = T, fontface = "bold") +
  coord_fixed() +
  theme_graph() + theme(legend.position = "none") +
  labs(title = "IESEG Twitter Network",subtitle = "Community detection")

IESEG_Net

