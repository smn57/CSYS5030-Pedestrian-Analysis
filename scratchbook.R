library(tidyverse)
library(lubridate)
library(zoo)

# sensors to remove: 
# 41, 55, >59

data <- read.csv2("pedestrians/Pedestrian_Counting_System_-_Monthly__counts_per_hour_.csv", sep = ",")
data %>% 
  filter(Sensor_ID < 59) %>%  # remove all late sensors, because no datapoints < 2022
  filter(Sensor_ID != 55) %>% # offline after being online, just started before covid
  filter(Sensor_ID != 41) %>% # was offline in 2019 too long to have good data
  mutate(Month = as.integer(factor(Month, levels=month.name))) %>% 
  mutate(Date_Time = make_datetime(Year, Month, Mdate, Time)) %>% 
  mutate(Date = make_date(Year, Month, Mdate)) %>% 
  filter(Date < as.Date("2022-01-01")) %>% # set boundary to end of 2021
  filter(Date > as.Date("2009-12-31")) %>% # set boundary to beginning of 2010
  subset(!(Month == 02 & Mdate == 29)) -> data # remove 29.02.



##################################################
# plot each for day
# very unclean overview on daily counts of all sensors
# DONE

data %>% 
  group_by(Sensor_ID, Date) %>% 
  summarise(Day_Counts = sum(Hourly_Counts)) %>% 
  # filter(Date < "2010-01-01") %>% 
  ggplot(aes(x = Date, color = factor(Sensor_ID))) +
  geom_line(aes(y = Day_Counts)) +
  scale_color_manual(values = our_colors) + 
  scale_x_date(date_breaks = '1 year', date_labels = "%Y")

##################################################
# sum of all with number of probes
# there is a correlation visible between totalcounts and number of probes
# rollmean for visualization to have a less jacky line
# DONE

data %>% 
  group_by(Date) %>% 
  summarise(Day_Counts = sum(Hourly_Counts), total_probes = length(unique(Sensor_ID))) %>% 
  mutate(total = rollmean(Day_Counts, 7) ) %>% 
  ggplot(aes(x = Date)) +
  geom_line(aes(y = total, color="totalcounts")) + 
  geom_line(aes(y = total_probes*10000, color="totalprobes")) + 
  scale_y_continuous(sec.axis = sec_axis(~./10000, name="totalprobes"))

# save this in dataframe for analysis
data %>% 
  group_by(Date) %>% 
  summarise(Day_Counts = sum(Hourly_Counts), total_probes = length(unique(Sensor_ID))) %>% 
  arrange(Date) %>% 
  select(-Date) %>% 
  write_csv("pedestrians/daycounts_totalprobes.csv")



##################################################
# sum of all divided by number of probes
# it is visible that the total number of pedestrians does not increase over the 
# years, but roughly stays the same but not for covid

data %>% 
  group_by(Date) %>% 
  summarise(Day_Counts = sum(Hourly_Counts), total_probes = length(unique(Sensor_ID))) %>% 
  mutate(total = Day_Counts/total_probes) %>% 
  ggplot(aes(x = Date, y = total)) +
  geom_line() 

# sum of all divided by number of probes with rollmean
data %>% 
  group_by(Date) %>% 
  summarise(Day_Counts = sum(Hourly_Counts), total_probes = length(unique(Sensor_ID))) %>% 
  mutate(total = rollmean(Day_Counts/total_probes, 7)) %>% 
  ggplot(aes(x = Date, y = total)) +
  geom_line() 

##################################################
# sum of all 
# number of pedestrian counts increase over the years

data %>% 
  group_by(Date) %>% 
  summarise(Day_Counts = sum(Hourly_Counts)) %>% 
  mutate(total = rollmean(Day_Counts, 7)) %>% 
  ggplot(aes(x = Date, y = total)) +
  geom_line() 


##################################################
# save data for probes
data %>% 
  group_by(Date) %>% 
  summarise(total_probes = length(unique(Sensor_ID)))  ->
  probes_per_day
write_csv(probes_per_day, "pedestrians/probes_per_day.csv")

##################################################
# one week in july
data %>% 
  filter(Year == 2016) %>% 
  filter(Month < 4) %>% 
  # filter(Mdate < 4) %>% 
  # filter(Sensor_ID %in% c(1, 6, 7, 13, 24, 38)) %>% 
  # group_by(Sensor_ID, Date_Time) %>% 
  ggplot(aes(x = Date_Time, color = factor(Sensor_ID))) +
  geom_line(aes(y = Hourly_Counts)) +
  scale_color_manual(values = our_colors)
 
##################################################
# stacked plot of sensors
# does not really work with days or hours

data %>% 
  # filter(Sensor_ID %in% c(7, 11, 12, 32, 35, 57)) %>% 
  # filter(Year == 2019) %>% 
  # filter(Month == 7) %>% 
  filter(Sensor_ID %in% c(7, 57)) %>% 
  group_by(Sensor_ID, Date) %>% 
  summarise(total = sum(Hourly_Counts)) %>% 
  ggplot(aes(x = Date, y = total, fill = factor(Sensor_ID))) +
  geom_area(position = "stack") 
  
##################################################
# all sensors
# DONE
data %>% 
  select(Sensor_Name, Sensor_ID) %>% 
  unique() %>% 
  arrange(Sensor_ID) %>% 
  write_csv("pedestrians/SensorID_SensorName.csv")
  view()

##################################################
# refactor data: datetime (hours) as rows and sensor ids as columns
# DONE

data %>% 
  # filter(Year %in% c(2019, 2020, 2021)) %>% 
  select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
  group_by(Date_Time, Sensor_ID) %>% 
  mutate(row = row_number()) %>% 
  pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
  select(-row) %>% 
  arrange(Date_Time) %>% 
  select(Date_Time, str_sort(names(.), numeric=TRUE)) ->
  datetime_sensor_id_refactor

datetime_sensor_id_refactor %>% 
  ungroup() %>% 
  mutate(Year = format(Date_Time, format="%Y")) %>% 
  filter(Year %in% c(2021)) %>% 
  select_if(~ !any(is.na(.))) %>% 
  select(-Date_Time, -Year) %>% 
  write_csv(file="pedestrians/datetime_sensor_id_refactor_2021.csv")


write_csv(datetime_sensor_id_refactor, "pedestrians/datetime_sensor_id_refactor_19-20-21.csv")

##################################################
# refactor data: date (days) as rows and sensor ids as columns

data %>% 
  select(Date, Sensor_ID, Hourly_Counts) %>% 
  group_by(Sensor_ID, Date) %>% 
  summarise(Daily_Counts = sum(Hourly_Counts)) %>% 
  #mutate(row = row_number()) %>% 
  pivot_wider(names_from = Sensor_ID, values_from = Daily_Counts) %>% 
  #select(-row) %>% 
  arrange(Date) %>% 
  select(Date, str_sort(names(.), numeric=TRUE)) ->
  date_sensor_id_refactor

for(i in 2010:2021) {
 date_sensor_id_refactor %>% 
  ungroup() %>% 
  mutate(Year = format(Date, format="%Y")) %>% 
  filter(Year %in% c(i)) %>% 
  select_if(~ !any(is.na(.))) %>% 
  select(-Date, -Year) %>% 
  write_csv(file=paste("pedestrians/daily_date_sensor_id_refactor_",i,".csv", sep=""))
}


##################################################
# save different months, not only years for a finer look
# DONE

months <- c(01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12)

for(yea in 2010:2021) {
  for(mon in months) {
    data %>% 
      filter(Year %in% yea) %>% 
      filter(Month %in% mon) %>% 
      select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
      group_by(Date_Time, Sensor_ID) %>% 
      mutate(row = row_number()) %>% 
      pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
      ungroup() %>% 
      select(-row) %>% 
      arrange(Date_Time) %>% 
      select(str_sort(names(.), numeric=TRUE)) %>% 
      select_if(~ !any(is.na(.))) %>% 
      select(-Date_Time) %>% 
      write_csv(file=paste("pedestrians/hourly_months/daily_date_sensor_id_refactor_",mon,"-",yea,".csv", sep=""))
  }
}
data %>% 
  filter(Year == 2018) %>% 
  filter(Month == 01) %>% 
  select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
  filter(Sensor_ID %in% c(31, 50)) %>% 
  group_by(Date_Time, Sensor_ID) %>% 
  mutate(row = row_number()) %>% 
  pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
  ungroup() %>% 
  select(-row) %>% 
  arrange(Date_Time) %>% 
  select(str_sort(names(.), numeric=TRUE)) %>% 
  select_if(~ !any(is.na(.)))


##################################################
# total probes with sum for months
data %>% 
  filter(Month %in% c(11)) %>% 
  group_by(Date) %>% 
  summarise(Day_Counts = sum(Hourly_Counts), total_probes = length(unique(Sensor_ID))) %>% 
  mutate(total = rollmean(Day_Counts, 7)/total_probes ) %>% 
  ggplot(aes(x = Date)) +
  geom_line(aes(y = total, color="totalcounts")) + 
  geom_line(aes(y = total_probes*100, color="totalprobes")) + 
  scale_y_continuous(sec.axis = sec_axis(~./100, name="totalprobes"))


##################################################
# total per day for each month 
data %>% 
  filter(Year %in% c(2019, 2020, 2021)) %>% 
  group_by(Year, Month, Mdate) %>% 
  summarise(total = sum(Hourly_Counts)) %>% 
  mutate(date = make_date(Month, Mdate)) %>% 
  ggplot(aes(x = date, y = total, color = factor(Year))) +
  geom_line() 

##################################################
# total per day for each month ADJUSTED to probes
# PLOT
# DONE

data %>% 
  select(-c(ID, Day, Sensor_Name)) %>% 
  filter(Year %in% c(2019, 2020, 2021)) %>% 
  filter(Year %!in% c(2010)) %>% 
  #filter(Year %in% c(2019, 2020, 2021)) %>% 
  #subset(!(Month == 02 & Mdate == 29)) %>% 
  group_by(Date_Time) %>% 
  summarise(total = sum(Hourly_Counts), total_probes = length(unique(Sensor_ID))) %>% 
  mutate(adjusted_total = rollmean(total/total_probes, 24)) %>% 
  mutate(Date_Time2 = format(Date_Time, format="%m-%d-%H")) %>% 
  mutate(Year = format(Date_Time, format="%Y")) %>% 
  mutate(idx = match(Date_Time2, unique(Date_Time2))) %>%  
  select(-Date_Time, -total_probes) %>% 
  ggplot(aes(x = idx, y = adjusted_total, color = factor(Year))) +
  geom_line() 
  # ggplot(aes(x = idx, y = adjusted_total, fill = factor(Year))) +
  # geom_area(position = "stack") 

# DATASET SAVE
data %>% 
  select(-c(ID, Day, Sensor_Name)) %>% 
  filter(Year %in% c(2019, 2020, 2021)) %>% 
  #filter(Year %!in% c(2009, 2010, 2022)) %>% 
  group_by(Date_Time) %>% 
  summarise(total = sum(Hourly_Counts), total_probes = length(unique(Sensor_ID))) %>% 
  mutate(adjusted_total = total/total_probes) %>% 
  mutate(Date_Time2 = format(Date_Time, format="%m-%d-%H")) %>% 
  mutate(Year = format(Date_Time, format="%Y")) %>% 
  mutate(idx = match(Date_Time2, unique(Date_Time2))) %>%  
  arrange(Date_Time) %>% 
  select(-Date_Time, -total_probes, -total) %>% 
  pivot_wider(names_from = Year, values_from = adjusted_total) %>% 
  #mutate("2013" = na.approx(`2013`)) %>% 
  #mutate("2014" = na.approx(`2014`)) %>% 
  #mutate("2015" = na.approx(`2015`)) %>% 
  #mutate("2016" = na.approx(`2016`)) %>% 
  #mutate("2017" = na.approx(`2017`)) %>% 
  select(-Date_Time2, -idx) %>% 
  #filter(idx %in% c(6555, 6579, 6627, 6651, 6675))
  #"["(rowSums(is.na(.)) > 0,)
  write_csv("pedestrians/hourly_adjusted_per_year_19-to-21.csv")
  
   
  
  
  
  
data %>% 
  filter(Year == 2017, Month == 10, Mdate == 01) %>% 
  group_by(Date_Time) %>% 
  summarise(total = sum(Hourly_Counts), total_probes = length(unique(Sensor_ID))) %>% 
  view()

  
  
  

##################################################
# total per year
# DONE

data %>% 
  group_by(Date) %>% 
  summarise(Day_Counts = sum(Hourly_Counts), total_probes = length(unique(Sensor_ID))) %>% 
  mutate(adjusted_total = Day_Counts/total_probes ) %>% 
  ungroup() %>% 
  mutate(Year = year(Date)) %>% 
  filter(Year %!in% c(2009, 2022)) %>% 
  mutate(MonDay = format(Date, format="%m-%d")) %>% 
  select(-c(Date, total_probes, Day_Counts)) %>% 
  pivot_wider(names_from = Year, values_from = adjusted_total) %>% 
  separate(MonDay, into=c("Month", "Day"), sep = "-") %>% 
  arrange(Month, Day) %>%  #-> month_day_years_total
  select(-c(Month, Day)) -> month_day_years_total

write_csv(month_day_years_total, "pedestrians/month_day_years_total.csv")

# remove feb 29
month_day_years_total %>% 
  subset(!(Month == "02" & Day == "29")) %>% 
  select(-c(Month, Day)) ->
  month_day_years_total_wo_feb

write_csv(month_day_years_total_wo_feb, "pedestrians/month_day_years_total_wo_feb.csv")


################################################## 
# plot different sensors on different plots to see the range of different sensors
# DONE

data %>% 
  select(Sensor_Name, Sensor_ID) %>% 
  unique() %>% 
  arrange(Sensor_ID) %>% 
  view()


data %>% 
  filter(Sensor_ID == 1) %>% 
  group_by(Date) %>% 
  summarise(Day_Counts = sum(Hourly_Counts)) %>% 
  arrange(Date) %>% 
  ggplot(aes(x = Date, y = Day_Counts)) + 
  geom_line() + 
  ggtitle(as.character(1)) +
  scale_x_date(limits = as.Date(c('2010-01-01','2021-12-31')))


plot_list = list()
for (id in 1:87) {
  p <- tryCatch({
    data %>% 
      filter(Sensor_ID == id) %>% 
      group_by(Date) %>% 
      summarise(Day_Counts = sum(Hourly_Counts)) %>% 
      arrange(Date) %>% 
      ggplot(aes(x = Date, y = Day_Counts)) +
      geom_line() + 
      ggtitle(as.character(id)) + 
      scale_x_date(limits = as.Date(c('2010-01-01','2021-12-31')))
  })
  tryCatch({
    plot_list[[id]] <- p
  })
}

pdf("plots.pdf")
for (i in 1:length(plot_list)) {
  print(plot_list[[i]])
}
dev.off()
 

################################################## 
# analysis of 2011 showed a big difference in sensors 2 and 7
# 7 has a really unpredictable behavior after July
# DONE?

data %>% 
  # filter(Year == 2011) %>% 
  filter(Sensor_ID %in% c(2, 11)) %>% 
  select(Date, Sensor_ID, Hourly_Counts) %>% 
  group_by(Date, Sensor_ID) %>% 
  summarise(Daily_Counts= sum(Hourly_Counts)) %>% 
  ungroup() %>% 
  arrange(Date) %>% 
  group_by(Sensor_ID) %>% 
  mutate(total = rollmean(Daily_Counts, 7)) %>% 
  ggplot(aes(x = Date, y = total, color = factor(Sensor_ID))) +
  geom_line()


################################################## 
# data for the 31.12.
# TODO

data %>% 
  filter()


################################################## 
# MI between pairs showed a high MI between 5 and 6, but not for 2015

data %>% 
  filter(Sensor_ID %in% c(5, 6)) %>% 
  filter(Year %in% c(2014, 2015, 2016)) %>% 
  #filter(Year %in% c(2014)) %>% 
  select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
  group_by(Sensor_ID) %>% 
  mutate(Total = rollmean(Hourly_Counts, 24)) %>% 
  ggplot(aes(x = Date_Time, y = Total, color = factor(Sensor_ID))) +
  geom_line()


data %>% 
  filter(Sensor_ID %in% c(9 ,18)) %>% 
  filter(Year %in% c(2013, 2014, 2015, 2016, 2017)) %>% 
  #filter(Year %in% c(2014)) %>% 
  select(Date, Sensor_ID, Hourly_Counts) %>% 
  group_by(Date, Sensor_ID) %>% 
  summarise(Daily_Counts = sum(Hourly_Counts)) %>% 
  group_by(Sensor_ID) %>% 
  mutate(Total = rollmean(Daily_Counts, 7)) %>% 
  ggplot(aes(x = Date, y = Total, color = factor(Sensor_ID))) +
  geom_line()

# 11 and 12 have a high TE
# they have the same values for some time - probably a measure or saving failure
data %>% 
  filter(Sensor_ID %in% c(31, 50)) %>% 
  filter(Year %in% c(2017, 2018)) %>% 
  #filter(Year %in% c(2014)) %>% 
  select(Date, Sensor_ID, Hourly_Counts) %>% 
  group_by(Date, Sensor_ID) %>% 
  summarise(Daily_Counts = sum(Hourly_Counts)) %>% 
  group_by(Sensor_ID) %>% 
  #mutate(Total = rollmean(Daily_Counts, 7)) %>% 
  mutate(Total = Daily_Counts) %>% 
  ggplot(aes(x = Date, y = Total, color = factor(Sensor_ID))) +
  geom_line()


################################################## 
# find a month with many sensors to compare "a typical" week
# -> 15.11.2018 has the most sensors - taking this week
# DONE

data %>% 
  select(Date_Time, Date, Month, Hourly_Counts, Sensor_ID) %>% 
  group_by(Date, Month) %>% 
  mutate(Total_probes = length(unique(Sensor_ID))) %>% 
  arrange(desc(Total_probes))

# plot data for this week
data %>% 
  filter(Year == 2018, Month == 11, Mdate %in% c(12, 13, 14, 15, 16, 17, 18)) %>% 
  ggplot(aes(x = Date_Time, y = Hourly_Counts, color = factor(Sensor_ID))) + 
  geom_line()

# save data
data %>% 
  filter(Year == 2018, Month == 11) %>% #, Mdate %in% c(12, 13, 14, 15, 16, 17, 18)) %>% 
  select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
  group_by(Date_Time, Sensor_ID) %>% 
  mutate(row = row_number()) %>% 
  pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
  select(-row) %>% 
  select(Date_Time, str_sort(names(.), numeric=TRUE)) %>% 
  arrange(Date_Time) %>% 
  ungroup() %>% 
  select_if(~ !any(is.na(.))) %>% 
  select(-Date_Time) %>% 
  write_csv(file="pedestrians/datetime_sensor_id_11-2018.csv")
  
# save data for each day
for (day in c(12, 13, 14, 15, 16, 17, 18)) {
  data %>%
    filter(Year == 2018, Month == 11, Mdate == day) %>%
    select(Date_Time, Sensor_ID, Hourly_Counts) %>%
    group_by(Date_Time, Sensor_ID) %>%
    mutate(row = row_number()) %>%
    pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>%
    select(-row) %>%
    select(Date_Time, str_sort(names(.), numeric = TRUE)) %>%
    arrange(Date_Time) %>%
    ungroup() %>%
    select_if( ~ !any(is.na(.))) %>%
    select(-Date_Time) %>%
    write_csv(file = paste("pedestrians/datetime_sensor_id_",day,"-11-2018.csv", sep=""))
}

# save whole week 
data %>%
  filter(Year == 2018, Month == 11, Mdate %in% c(12, 13, 14, 15, 16, 17, 18)) %>%
  select(Date_Time, Sensor_ID, Hourly_Counts) %>%
  group_by(Date_Time, Sensor_ID) %>%
  mutate(row = row_number()) %>%
  pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>%
  select(-row) %>%
  select(Date_Time, str_sort(names(.), numeric = TRUE)) %>%
  arrange(Date_Time) %>%
  ungroup() %>%
  select_if(~ !any(is.na(.))) %>%
  select(-Date_Time) %>%
  write_csv(file = "pedestrians/datetime_sensor_id_week-11-2018.csv")

# plot whole week
data %>%
  filter(Year == 2018, Month == 11, Mdate %in% c(12, 13, 14, 15, 16, 17, 18)) %>%
  select(Date_Time, Sensor_ID, Hourly_Counts) %>%
  group_by(Date_Time, Sensor_ID) %>% 
  ggplot(aes(x = Date_Time, y = Hourly_Counts, color = factor(Sensor_ID))) +
  geom_line()


################################################## 
# sensor id location with map
# buhh
library(maps)


locations <- read.csv2("pedestrians/Pedestrian_Counting_System_Sensor_Locations.csv", sep = ",")

data %>% 
  select(Sensor_ID) %>% 
  unique() -> sensors_ids

locations %>% 
  select(sensor_id, latitude, longitude) %>% 
  filter(sensor_id %in% sensors_ids$Sensor_ID) %>%
  arrange(sensor_id) %>%
  # get min and max of both coordinates
  mutate(min_lat = min(latitude), max_lat = max(latitude), min_long = min(longitude), max_long = max(longitude)) %>% 
  select(-sensor_id, -latitude, -longitude) %>% 
  unique()  %>% 
  # convert strings to numeric
  mutate(min_lat = as.numeric(min_lat), max_lat = as.numeric(max_lat), min_long = as.numeric(min_long), max_long = as.numeric(max_long)) -> min_max_coords


# get a map of Melbourne of the database "world" with maps
#map("world", xlim = c(min_max_coords$min_long, min_max_coords$max_long), ylim = c(min_max_coords$min_lat, min_max_coords$max_lat), fill = TRUE, col = "grey", mar = c(0, 0, 0, 0))
map.cities()


################################################## 
# find year where the most sensors are available
# 2018/2020 - 31
# 2021 - 29
# 2019 - 28
# data already exists 
# DONE

data %>% 
  # filter(Year %in% c(2019, 2020, 2021)) %>% 
  select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
  group_by(Date_Time, Sensor_ID) %>% 
  mutate(row = row_number()) %>% 
  pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
  select(-row) %>% 
  arrange(Date_Time) %>% 
  select(Date_Time, str_sort(names(.), numeric=TRUE)) %>% 
  ungroup() %>% 
  mutate(Year = format(Date_Time, format="%Y")) -> datetime_sensor_data

for (ye in 2010:2021) {
  datetime_sensor_data %>% 
    filter(Year == ye) %>% 
    select_if(~ !any(is.na(.))) %>% 
    ncol() -> num
  print(paste(ye, num)) 
}


################################################## 
# get data for different weekdays of year 2018

data %>% 
  filter(Year == 2018) %>% 
  select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
  group_by(Date_Time, Sensor_ID) %>% 
  mutate(row = row_number()) %>% 
  pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
  select(-row) %>% 
  arrange(Date_Time) %>% 
  select(Date_Time, str_sort(names(.), numeric=TRUE)) %>% 
  ungroup() %>% 
  mutate(Weekday = format(Date_Time, format="%A")) %>% 
  filter(Weekday == "Monday") %>% 
  # remove Weekday and Date_Time 
  select(-Weekday, -Date_Time) %>%
  write_csv(file = "pedestrians/datetime_sensor_id_monday-2018.csv")


# put above code in a loop over all weekdays
for (day in c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")) {
  data %>% 
    filter(Year == 2018) %>% 
    select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
    group_by(Date_Time, Sensor_ID) %>% 
    mutate(row = row_number()) %>% 
    pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
    select(-row) %>% 
    arrange(Date_Time) %>% 
    select(Date_Time, str_sort(names(.), numeric=TRUE)) %>% 
    ungroup() %>% 
    # remove columns where there is any NA
    select_if(~ !any(is.na(.))) %>%
    mutate(Weekday = format(Date_Time, format="%A")) %>% 
    filter(Weekday == day) %>% 
    # remove Weekday and Date_Time 
    select(-Weekday, -Date_Time) %>%
    write_csv(file = paste("pedestrians/datetime_sensor_id_", tolower(day), "-2018.csv", sep=""))
} 

################################################## 
# locations filter
locations %>% 
  select(sensor_id, sensor_description, location) %>% 
  arrange(sensor_id) -> sensor_id_name_location

weekday_AIS %>% 
  select(Sensor) %>% 
  unique() -> used2018sensors

sensor_id_name_location %>% 
  select(sensor_id, location) %>% 
  filter(sensor_id < 59) %>%  # remove all late sensors, because no datapoints < 2022
  filter(sensor_id != 55) %>% # offline after being online, just started before covid
  filter(sensor_id != 41) %>% 
  filter(sensor_id %in% used2018sensors$Sensor) %>% 
  # remove ( ) from location
  mutate(location = gsub("[()]", "", location)) %>%
  # save to csv
  write_csv(file = "pedestrians/sensor_id_location_2018.csv")


################################################## 
# plot a heatmap with hours on the x axis and the days of the week on the y axis

colfunc<-colorRampPalette(c("white","yellow","red","black"))

data %>% 
  filter(Year == 2021) %>% 
  # get the sum of Hourly_Counts for each hour of each day of the week
  group_by(Day, Time) %>%
  summarise(Hourly_Counts = sum(Hourly_Counts)) %>%
  ungroup() %>% 
  # order weekdays by day of the week
  mutate(Day = factor(Day, levels = c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"))) %>%
  ggplot(aes(x = Time, y = Day, fill = Hourly_Counts)) +
  geom_tile() +
  scale_fill_gradientn(colours = colfunc(100)) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5)) +
  labs(x = "Time", y = "Day", fill = "Hourly Counts") +
  ggtitle("Pedestrian Counts in 2018") 

  
# use above code in a for loop over the years 2010 to 2021 and save plots in an array 
plots <- list()
for (ye in 2010:2021) {
  plots[[ye]] <- data %>% 
    filter(Year == ye) %>% 
    # get the sum of Hourly_Counts for each hour of each day of the week
    group_by(Day, Time) %>%
    summarise(Hourly_Counts = sum(Hourly_Counts)) %>%
    ungroup() %>% 
    # order weekdays by day of the week
    mutate(Day = factor(Day, levels = c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"))) %>%
    ggplot(aes(x = Time, y = Day, fill = Hourly_Counts)) +
    geom_tile() +
    scale_fill_gradientn(colours = colfunc(100)) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5)) +
    labs(x = "Time", y = "Day", fill = "Hourly Counts") +
    ggtitle(paste("Pedestrian Counts in", ye))
}

# save plots in pdf
pdf("pedestrians/weekday_time_heatmap.pdf", width = 11, height = 6)
for (i in 1:length(plots)) {
  print(plots[[i]])
}
dev.off()






################################################## 
library(tmap)
library(sf)
library(sp)

locations <- read.csv2("pedestrians/Pedestrian_Counting_System_Sensor_Locations.csv", sep = ",")

data %>% 
  select(Sensor_ID) %>% 
  unique() -> sensors_ids

locations %>% 
  select(sensor_id, latitude, longitude) %>% 
  filter(sensor_id %in% sensors_ids$Sensor_ID) %>%
  arrange(sensor_id) %>%
  # get min and max of both coordinates
  mutate(min_lat = min(latitude), max_lat = max(latitude), min_long = min(longitude), max_long = max(longitude)) %>% 
  select(-sensor_id, -latitude, -longitude) %>% 
  unique()  %>% 
  # convert strings to numeric
  mutate(min_lat = as.numeric(min_lat), max_lat = as.numeric(max_lat), min_long = as.numeric(min_long), max_long = as.numeric(max_long)) -> 
  min_max_coords 


################################################## 
# months 
# maybe not a good idea, because sensors are too fluctuation and I cant find enough
# years to have more months
# DISCARD

for (month in c(1:12)) {
  data %>% 
    filter(Year %in% c(2019:2021)) %>% 
    select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
    group_by(Date_Time, Sensor_ID) %>% 
    mutate(row = row_number()) %>% 
    pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
    select(-row) %>% 
    arrange(Date_Time) %>% 
    select(Date_Time, str_sort(names(.), numeric=TRUE)) %>% 
    ungroup() %>% 
    # remove columns where there is any NA
    select_if(~ !any(is.na(.))) %>%
    # get month from Date_Time
    mutate(Month = as.numeric(format(Date_Time, format="%m"))) %>%
    filter(Month == month) %>% 
    # remove Weekday and Date_Time 
    select(-Date_Time, -Month) %>%
    write_csv(file = paste("pedestrians/datetime_sensor_id_", tolower(month), "-1921.csv", sep=""))
} 

data %>% 
  filter(Year %in% c(2019:2021)) %>% 
  select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
  group_by(Date_Time, Sensor_ID) %>% 
  mutate(row = row_number()) %>% 
  pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
  select(-row) %>% 
  arrange(Date_Time) %>% 
  select(Date_Time, str_sort(names(.), numeric=TRUE)) %>% 
  ungroup() %>% 
  # remove columns where there is any NA
  select_if(~ !any(is.na(.))) %>%
  select(-Date_Time) %>%
  write_csv(file = "pedestrians/datetime_sensor_id_1921.csv")


################################################## 
# TODO: dataset with sensors 2 and 9 for local AIS calculation and plotting for 2018



################################################## 
# get distance between sensors and save it
# DONE
library(geosphere)

# use sensor_id_name_location to and distm function to calculate the distance between all sensors
sensor_id_name_location %>% 
  filter(sensor_id %in% used2018sensors$Sensor) %>% 
  select(-sensor_description) %>% 
  # remove ( and ) from location column
  mutate(location = gsub("[()]", "", location)) %>% 
  # have to columns sensor1 and sensor2 with all combinations of sensor_id
  select(sensor1 = sensor_id, sensor2 = sensor_id, location1 = location, location2 = location) %>%
  expand(sensor1, sensor2) %>%
  right_join(., sensor_id_name_location %>% 
               #filter(sensor_id %in% used2018sensors$Sensor) %>% 
               select(-sensor_description) %>% 
               # remove ( and ) from location column
               mutate(location = gsub("[()]", "", location)) %>% 
               select(sensor2 = sensor_id, location2 = location), by = "sensor2") %>%
  right_join(., sensor_id_name_location %>% 
               #filter(sensor_id %in% used2018sensors$Sensor) %>% 
               select(-sensor_description) %>% 
               # remove ( and ) from location column
               mutate(location = gsub("[()]", "", location)) %>% 
               select(sensor1 = sensor_id, location1 = location), by = "sensor1") %>%
  # remove rows where sensor1 == sensor2
  filter(sensor1 != sensor2) %>%
  # remove rows where sensor1 > sensor2
  #filter(sensor1 < sensor2) %>%
  select(sensor1, sensor2, location1, location2) %>%
  # split location1 and location2 in latitude and longitude
  separate(location1, c("lat1", "long1"), sep = ", ") %>%
  separate(location2, c("lat2", "long2"), sep = ", ") %>%
  # convert strings to numeric
  mutate(lat1 = as.numeric(lat1), long1 = as.numeric(long1), lat2 = as.numeric(lat2), long2 = as.numeric(long2)) %>% 
  rowwise() %>% 
  # calculate distance between sensors
  mutate(distance = distm(c(long1, lat1), c(long2, lat2), fun = distHaversine)) %>%
  # remove columns lat1, long1, lat2, long2
  select(-lat1, -long1, -lat2, -long2) %>%
  # rename distance[,1] to distance
  rename(distance = distance) %>% 
  # combinde sensor1 and sensor2 into sensors, in 1_2 format 
  mutate(sensors = paste(sensor1, sensor2, sep = "_")) %>%
  # remove sensor1 and sensor2
  select(-sensor1, -sensor2) %>%
  select(sensors, distance) %>% 
  # create histogram
  ggplot(aes(x = distance)) +
  geom_histogram(bins = 100) +
  labs(x = "Distance between sensors", y = "Count") +
  # title 
  ggtitle("Histogram of distance between sensors") -> plot

# save plot
ggsave("pedestrians/histogram_distance_between_sensors.png", plot = plot, width = 10, height = 5, dpi = 300)

  
  
  
  view()#-> sensor_distances


################################################## 
# pick sensors directly and find a year where they all perform
# can't really find years where there are more than 4 sensors of the ones I am
# interested in. Unfortunately cannot go further from here

data %>% 
  filter(Sensor_ID %in% c(9, 23, 5, 6, 22, 15)) %>%
  filter(Year == 2019) %>% 
  # plot Hourly_Counts for each sensor
  ggplot(aes(x = Date_Time, y = Hourly_Counts, color = factor(Sensor_ID))) +
  geom_line() +
  facet_wrap(~Sensor_ID, scales = "free") +
  theme_minimal() +
  theme(legend.position = "none") +
  labs(x = "Date_Time", y = "Hourly_Counts", title = "Hourly_Counts for each sensor") +
  scale_x_datetime(date_breaks = "1 month", date_labels = "%b %Y") +
  scale_y_continuous(breaks = seq(0, 100, 10)) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1)) +
  theme(legend.position = "none") + 
  # use our_colors
  scale_color_manual(values = our_colors) 

data %>% 
  filter(Sensor_ID %in% c(3, 9, 23, 24, 5, 6, 22, 15)) %>%
  filter(Year == 2010) %>%
  select(Date_Time, Sensor_ID, Hourly_Counts) %>% 
  group_by(Date_Time, Sensor_ID) %>% 
  mutate(row = row_number()) %>% 
  pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
  select(-row) %>% 
  arrange(Date_Time) %>% 
  select(Date_Time, str_sort(names(.), numeric=TRUE)) %>%  
  ungroup() %>% 
  select_if(~ !any(is.na(.)))# %>% 
  select(-Date_Time, -Year) 

################################################## 
data %>% 
    filter(Year == 2018) %>% 
    filter(Sensor_ID == 15) %>% 
    group_by(Month) %>% 
    summarise(total = sum(Hourly_Counts)) %>% 
    ggplot(aes(x = Month, y = total)) +
    geom_point()
  
  %>% 
    write.csv2(file = "pedestrians/totalcounts_2018.csv", row.names = FALSE)
    
################################################## 
# save data for sensors 1 and 2 for 2018 
  
data %>% 
  filter(Year == 2018) %>% 
  filter(Sensor_ID %in% c(1,2)) %>% 
    select(Sensor_ID, Date_Time, Hourly_Counts) %>% 
  pivot_wider(names_from = Sensor_ID, values_from = Hourly_Counts) %>% 
  select_if(~ !any(is.na(.))) %>% 
    arrange(Date_Time) %>% 
    select(-Date_Time) %>% 
  write_csv(file = "pedestrians/sensors1_2_2018.csv")
    
  
  
  