library(tidyverse)
library(dplyr)
library(pracma)
library(ggplot2)
library(lubridate)
library(tigris)
library(MatchIt)
source('downtown_loc.R')
source('college_loc.R')
source('mapToTract.R')

panel.cor <- function(x, y, digits=2, prefix="", cex.cor) 
{
  usr <- par("usr"); on.exit(par(usr)) 
  par(usr = c(0, 1, 0, 1)) 
  r <- abs(cor(x, y)) 
  txt <- format(c(r, 0.123456789), digits=digits)[1] 
  txt <- paste(prefix, txt, sep="") 
  if(missing(cex.cor)) cex <- 0.8/strwidth(txt) 
  
  test <- cor.test(x,y) 
  # borrowed from printCoefmat
  Signif <- symnum(test$p.value, corr = FALSE, na = FALSE, 
                   cutpoints = c(0, 0.001, 0.01, 0.05, 0.1, 1),
                   symbols = c("***", "**", "*", ".", " ")) 
  
  text(0.5, 0.5, txt, cex = cex * r) 
  text(.8, .8, Signif, cex=cex, col=2) 
}


get_unique_loc <- function(data) {
  "
  Only get the unique combinations of LAT LNG
  "
  data <- data %>%
    select(-c(START, END, COUNT, AVAIL, DATE, DAY)) %>%
    distinct(LAT, LNG)
  
  return(data)
}


dist_to_downtown <- function(data) {
  MI_RADIUS <- 3956
  downtown_loc <- get_downtown()
  loc <- get_unique_loc(data)
  
  # check whether their distance is within the college_locs
  for (i in 1:dim(loc)[1]) {
    min_dist <- 2000
    for (j in 1:dim(downtown_loc)[1]) {
      dist <- haversine(c(loc$LAT[i], loc$LNG[i]), c(downtown_loc$LAT[j], downtown_loc$LNG[j]), MI_RADIUS)
      if (dist < min_dist) { # if dist is smaller than min dist 
        min_dist <- dist
      }
    }
    data[(data$LAT == loc$LAT[i] | data$LNG == loc$LNG[i]),]$DOWNDIST <- min_dist
  }
  
  return(data)
}


dist_to_college <- function(data) {
  MI_RADIUS <- 3956
  college_loc <- get_colleges()
  loc <- get_unique_loc(data)
  
  # check whether their distance is within the college_locs
  for (i in 1:dim(loc)[1]) {
    min_dist <- 2000
    for (j in 1:dim(college_loc)[1]) {
      dist <- haversine(c(loc$LAT[i], loc$LNG[i]), c(college_loc$LAT[j], college_loc$LNG[j]), MI_RADIUS)
      if (dist < min_dist) { # if dist is smaller than min dist 
        min_dist <- dist
      }
    }
    data[(data$LAT == loc$LAT[i] | data$LNG == loc$LNG[i]),]$COLLDIST <- min_dist
  }
  
  return(data)
}


near_college_check <- function(data, buffer) {
  MI_RADIUS <- 3956
  college_loc <- get_colleges()
  loc <- get_unique_loc(data)
  
  # check whether their distance is within the college_locs
  for (i in 1:dim(loc)[1]) {
    for (j in 1:dim(college_loc)[1]) {
      dist <- haversine(c(loc$LAT[i], loc$LNG[i]), c(college_loc$LAT[j], college_loc$LNG[j]), MI_RADIUS)
      if (dist <= buffer) {
        data[(data$LAT == loc$LAT[i] | data$LNG == loc$LNG[i]),]$NEARCOLLEGE <- TRUE
      }
    }
  }
  
  return(data)
}


find_census_val_riwac <- function(data, ri_data, census_name, col_name) {
  # get unique lat lng locations -> therefore get unique GEOIDs
  loc <- get_unique_loc(data) %>%
         mapToTract() %>%
         mutate(rounded_geocode = str_sub(as.character(GEOID), 1, 11))
  
  # necessary step for parameterized column names
  census_name <- c(census_name)
  col_name <- c(col_name)
  
  
  for (i in 1:dim(loc)[1]) {
    row <- which(grepl(loc$GEOID[i], ri_wac$w_geocode))
    if (length(row) != 0) { # if there exists the block geoid in ri_wac
      data[data$GEOID == loc$GEOID[i], c(col_name)] <- ri_data[row, c(census_name)]
      
    } else { # if block geoid doesn't exist in ri_wac
      # get the mean of the census_name values for each ROUNDED_GEOID (basically for each tract)
      sub_ri_wac <- ri_data %>%
        group_by(ROUNDED_GEOID) %>%
        summarise(COL = mean(get(census_name)))
      
      row <- which(grepl(loc$rounded_geocode[i], sub_ri_wac$ROUNDED_GEOID))
      data[data$ROUNDED_GEOID == loc$rounded_geocode[i], c(col_name)] <- sub_ri_wac$COL[row]
    }
  }
  return(data)
}


find_census_val_ridat <- function(data, ri_data, census_name, col_name) {
  # get unique lat lng locations -> therefore get unique GEOIDs
  loc <- get_unique_loc(data) %>%
         mapToTract() %>%
         mutate(rounded_geocode = str_sub(as.character(GEOID), 1, 11))
  
  for (i in 1:dim(loc)[1]) {
    row <- which(grepl(loc$rounded_geocode[i], ri_data$GEOID))
    if (length(row) != 0) { 
      data[data$ROUNDED_GEOID == loc$rounded_geocode[i], c(col_name)] <- ri_data[row, c(census_name)]
      
    } else { # if the GEOID from data doesn't exist in ri_data
      data[data$ROUNDED_GEOID == loc$rounded_geocode[i], c(col_name)] <- NA
    }
  }
  return(data)
}


get_density <- function(data) {
  MI_RADIUS <- 3956
  sub_data <- data %>%
              group_by(DATE, ROUNDED_GEOID) %>%
              summarise(AVG_COUNT = mean(COUNT),
                        LAT = LAT,
                        LNG = LNG)
  print(head(data))
  print(head(sub_data))
  
  for (i in 1:dim(data)[1]) {
    sum <- 0
    # ssub_data <- subset(sub_data, data$DATE[i] == sub_data$DATE)
    ssub_data <- sub_data[(data$DATE[i] == sub_data$DATE),]
    for (j in 1:dim(ssub_data)[1]) {
      dist <- haversine(c(data$LAT[i], data$LNG[i]), c(ssub_data$LAT[j], ssub_data$LNG[j]), MI_RADIUS)
      if (dist < 0.15) {
        sum <- sum + ssub_data$AVG_COUNT[j]
      }
    }
    data$DENSITY[i] <- sum
  }
  
  return(data)
}


# -------------- PREP PICKUP DATA --------------------
pickups <- read_csv("~/PVD Summer Research/average_num_available/intervalCountsLATLNG.csv")
pickups <- pickups %>%
  filter(DATE >= "2019-4-15" & DATE <= "2019-6-15") %>%
  mutate(DOWNDIST = 0, COLLDIST = 0, NEARCOLLEGE = FALSE) %>%
  dist_to_downtown() %>%
  dist_to_college() %>%
  near_college_check(0.2)


# -------------- GEOID RETRIEVAL ---------------------
# map to census tract
data <- mapToTract(pickups)


# -------------- GET CENSUS NUMBERS ------------------
ri_wac <- read_csv("~/PVD Summer Research/college/ri_wac_S000_JT00_2017.csv") %>%
  mutate(ROUNDED_GEOID = str_sub(as.character(w_geocode), 1, 11))

ri_dat <- read_csv("~/PVD Summer Research/pvd_summer/censusData/riData.csv")

data <- data %>%
  mutate(ROUNDED_GEOID = str_sub(as.character(GEOID), 1, 11)) %>%
  mutate(TOTJOBS = 0, POP = 0,  AUTO = 0, PERCAPITAINC = 0,
         PUBLIC  = 0, WALK = 0, COLLEGE = 0, POVERTY = 0) %>%
  find_census_val_riwac(ri_wac, "C000", "TOTJOBS") %>%
  find_census_val_ridat(ri_dat, "Pop", "POP") %>%
  find_census_val_ridat(ri_dat, "perCapitaInc", "PERCAPITAINC") %>%
  find_census_val_ridat(ri_dat, "auto", "AUTO") %>%
  find_census_val_ridat(ri_dat, "public", "PUBLIC") %>%
  find_census_val_ridat(ri_dat, "walk", "WALK") %>%
  find_census_val_ridat(ri_dat, "college", "COLLEGE") %>%
  find_census_val_ridat(ri_dat, "Poverty", "POVERTY")

# separate the rows with NA to find which geoids are causing errors
na_data <- data[!complete.cases(data), ]

data <- data %>%
        na.omit()


# ------- FIND CORRELATION BETWEEN VAIRABLES ---------
# pairs(data[, c(3, 9, 10, 14:21)], lower.panel=panel.smooth, upper.panel=panel.cor)


# -------------- LINEAR REGRESSION MODEL -------------
## DO TRANSFORMATIONS ON HIGH VARIANCE
## FIND HIGHEST INDICES FROM RESIDUAL AND UNDERSTAND WHERE THEY ARE COMING FROM

# log0 = error, so added 1 to the count when taking the log
# model <- lm(log(COUNT+1) ~ COLLDIST + log(DOWNDIST+1) + TOTJOBS + log(POP+1) + log(PERCAPITAINC+1) +
#                     AUTO + PUBLIC + WALK + COLLEGE + POVERTY, data = data)
# print(summary(model))
# print(summary(model)$coefficient)
# print(summary(model)$r.squared)
# print(sigma(model)/mean(data$COUNT))
# 
# ## plot each variable against residuals to see the variable datapoints' distribution
# plot(data$POVERTY,model$residuals)
# 
# ## find the outliers with the highest squared residuals
# o <- order(model$residuals^2, decreasing=T)
# print(data[o[1:20],c(5:21)])
# 
# 
# layout(matrix(c(1,2,3,4),2,2)) # optional 4 graphs/page
# plot(model)
# 
# 
# ----------- MATCHING & PROPENSITY SCORES -----------
## add new column of close or far from college value
# matching_data <- data %>%
#                  mutate(NEARCOLLEGE = ifelse(NEARCOLLEGE, 1, 0)) %>%
#                  ungroup()
# matching_data <- as.data.frame(matching_data)
# str(matching_data)
# 
# 
# # ------------------- PREPROCESSING ------------------
# ## 1. Standardized Difference
# treated <- (matching_data$NEARCOLLEGE==1)
# cov <- matching_data[, c(15, 9, 16, 18, 22)]
# std.diff <- apply(cov, 2, function(x) 100*(mean(x[treated]) - mean(x[!treated])) / (sqrt(0.5*(var(x[treated]) + var(x[!treated])))))
# abs(std.diff)
# 
# ## 2. Chi-square Test
# library("RItools")
# 
# xBalance(NEARCOLLEGE ~ TOTJOBS + DOWNDIST + POP + PERCAPITAINC + POVERTY, data = matching_data,
#          report = c("chisquare.test"))
# 
# 
# # ----------- PROPENSITY SCORE ESTIMATION -------------
# ps <- glm(NEARCOLLEGE ~ TOTJOBS + DOWNDIST + POP + PERCAPITAINC + POVERTY, data = matching_data,
#           family = binomial())
# summary(ps)
# 
# 
# matching_data$psvalue <- predict(ps, type = "response")
# library("Hmisc")
# histbackback(split(matching_data$psvalue, matching_data$NEARCOLLEGE), main = "Propensity Score Before Matching", 
#              xlab=c("control", "treatment"))
# 
# 
# ## conventional matching using Mahalanobis distance - DOESNT WORK
# m.mahal <- matchit(NEARCOLLEGE ~ TOTJOBS + DOWNDIST + POP + PERCAPITAINC + POVERTY, data = matching_data,
#                    mahvars = c("TOTJOBS", "DOWNDIST", "POP", "PERCAPITAINC", "POVERTY"),
#                    caliper = 0.25, calclosest = TRUE, replace = TRUE, distance = "mahalanobis")
# summary(m.mahal)
# 
# m.nn <- matchit(NEARCOLLEGE ~ TOTJOBS + DOWNDIST + POP + PERCAPITAINC + POVERTY, data = matching_data,
#                 method = "nearest", ratio = 2)
# summary(m.nn)
