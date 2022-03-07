library(dplyr)
library(readr)
library(igraph)

### start parameters ###
# start from the link to a CSV dataset of Instagram posts returned by a CrowdTangle Search export
ct_histdata_csv_1 = "" # copy/post the link to the CSV from the email recieved
# ct_histdata_csv_2 = ""
coordination_internal <- "60 secs" # set your coordination internal
percentile_edge_weight <- 0.9 # determines the minimum number of repetition used to conside an account as coordinated
### end parameters ###

csv_v <- c(ct_histdata_csv_1) # this could be useful in case you want to merge multiple CSVs
# csv_v <- c(ct_histdata_csv_1, ct_histdata_csv_2)

allposts <- NULL

for (i in 1:length(csv_v)) {
  
  df <- readr::read_csv(col_types = cols(
    .default = col_skip(),
    type = col_character(),
    date = col_character(),
    imageText = col_character(),
    account.name = col_character(),
    account.handle = col_character(),
    postUrl = col_character()),
    file =  csv_v[i])
  
  allposts <- rbind(allposts, df)
  
}

allposts <- allposts %>% distinct()

# remove posts where img_text is empty
df <- subset(allposts, !is.na(allposts$imageText))
rm(allposts)

# extract a frequency table of unique identical img_text in the dataset
unique_imageText <- as.data.frame(table(df$imageText))
names(unique_imageText) <- c("imageText", "ct_shares")
unique_imageText <- subset(unique_imageText, unique_imageText$ct_shares >1)
unique_imageText$imageText <- as.character(unique_imageText$imageText)
df <- subset(df, df$imageText %in% unique_imageText$imageText)
df$account.url <- paste0("https://www.instagram.com/", df$account.handle)

# for each unique img_text execute CooRnet code to find coordination
datalist <- list()

# progress bar
total <- nrow(unique_imageText)
pb <- txtProgressBar(max=total, style=3)
for (i in 1:nrow(unique_imageText)) {
  utils::setTxtProgressBar(pb, pb$getVal()+1)
  current_imageText <- unique_imageText$imageText[i]
  dat.summary <- subset(df, df$imageText==current_imageText)
  if (length(unique(dat.summary$account.url)) > 1) {
    dat.summary <- dat.summary %>%
      dplyr::mutate(cut = cut(as.POSIXct(date), breaks = coordination_internal)) %>%
      dplyr::group_by(cut) %>%
      dplyr::mutate(count=n(),
                    account.url=list(account.url),
                    share_date=list(date),
                    imageText = current_imageText) %>%
      dplyr::select(cut, count, account.url, share_date, imageText) %>%
      dplyr::filter(count > 1) %>%
      unique()
    datalist <- c(list(dat.summary), datalist)
    rm(dat.summary)
  }
}

datalist <- tidytable::bind_rows.(datalist)

if(nrow(datalist)==0){
  stop("there are not enough shares!")
}

coordinated_shares <- tidytable::unnest.(datalist)
rm(datalist)
# mark the coordinated shares in the data set
df$is_coordinated <- ifelse(df$imageText %in% coordinated_shares$imageText &
                              df$date %in% coordinated_shares$share_date &
                              df$account.url %in% coordinated_shares$account.url, TRUE, FALSE)
el <- coordinated_shares[,c("account.url", "imageText", "share_date")] # drop unnecessary columns
v1 <- data.frame(node=unique(el$account.url), type=1) # create a dataframe with nodes and type 0=imageText 1=page
v2 <- data.frame(node=unique(el$imageText), type=0)
v <- rbind(v1,v2)
g2.bp <- igraph::graph.data.frame(el, directed = T, vertices = v) # makes the bipartite graph
g2.bp <- igraph::simplify(g2.bp, remove.multiple = T, remove.loops = T, edge.attr.comb = "min") # simplify the bipartite network to avoid problems with resulting edge weight in projected network
full_g <- suppressWarnings(igraph::bipartite.projection(g2.bp, multiplicity = T)$proj2) # project entity-entity network
all_account_info <- df %>%
  dplyr::group_by(account.url) %>%
  dplyr::mutate(account.name.changed = ifelse(length(unique(account.name))>1, TRUE, FALSE), # deal with account.data that may have changed (name, handle)
                account.name = paste(unique(account.name), collapse = " | "),
                account.handle.changed = ifelse(length(unique(account.handle))>1, TRUE, FALSE),
                account.handle = paste(unique(account.handle), collapse = " | ")) %>%
  dplyr::summarize(shares = n(),
                   coord.shares = sum(is_coordinated==TRUE),
                   account.name = dplyr::first(account.name), # name
                   account.name.changed = dplyr::first(account.name.changed),
                   account.handle.changed = dplyr::first(account.handle.changed), # handle
                   account.handle = dplyr::first(account.handle))
# rm(df, coordinated_shares)
# add vertex attributes
vertex.info <- subset(all_account_info, as.character(all_account_info$account.url) %in% igraph::V(full_g)$name)
V(full_g)$shares <- sapply(V(full_g)$name, function(x) vertex.info$shares[vertex.info$account.url == x])
V(full_g)$coord.shares <- sapply(V(full_g)$name, function(x) vertex.info$coord.shares[vertex.info$account.url == x])
V(full_g)$account.name <- sapply(V(full_g)$name, function(x) vertex.info$account.name[vertex.info$account.url == x])
V(full_g)$name.changed <- sapply(V(full_g)$name, function(x) vertex.info$account.name.changed[vertex.info$account.url == x])
V(full_g)$account.handle <- sapply(V(full_g)$name, function(x) vertex.info$account.handle[vertex.info$account.url == x])
V(full_g)$handle.changed <- sapply(V(full_g)$name, function(x) vertex.info$account.handle.changed[vertex.info$account.url == x])
# keep only highly coordinated entities
V(full_g)$degree <- igraph::degree(full_g)
q <- quantile(E(full_g)$weight, percentile_edge_weight) # set the percentile_edge_weight number of repetedly coordinated link sharing to keep
highly_connected_g <- igraph::induced_subgraph(graph = full_g, vids = V(full_g)[V(full_g)$degree > 0 ]) # filter for degree
highly_connected_g <- igraph::subgraph.edges(highly_connected_g, eids = which(E(highly_connected_g)$weight >= q),delete.vertices = T) # filter for edge weight
# find and annotate nodes-components
V(highly_connected_g)$component <- igraph::components(highly_connected_g)$membership
V(highly_connected_g)$cluster <- igraph::cluster_louvain(highly_connected_g)$membership # add cluster to simplyfy the analysis of large components
V(highly_connected_g)$degree <- igraph::degree(highly_connected_g) # re-calculate the degree on the subgraph
V(highly_connected_g)$strength <- igraph::strength(highly_connected_g) # sum up the edge weights of the adjacent edges for each vertex
highly_connected_coordinated_entities <- igraph::as_data_frame(highly_connected_g, "vertices")
rownames(highly_connected_coordinated_entities) <- 1:nrow(highly_connected_coordinated_entities)

highly_c_list <- list(highly_connected_g, highly_connected_coordinated_entities, q) # output in list format. Includes the list of coordinated accounts and a graphml file that you can visualize in Gephi

# export output files
write.csv(highly_connected_coordinated_entities, "highly_connected_coordinated_entities.csv")
write.graph(highly_connected_g, "highly_connected_g.graphml", format="graphml")