#' Tidy iVolatility options .csv files
#'
#' @description{
#' tidy_options produces a tidy dataset from downloaded iVolatility.com files.
#' Download data from \href{http://www.ivolatility.com/data_download.j}{http://www.ivolatility.com/data_download.j}
#'
#'    \itemize{
#'       \item Individual contracts (Raw IV) data
#'       \item include greeks in file download
#'       \item place files in folder under the working directory
#'       \item ensure that market closed dates are current
#'     }
#' }
#' @param symbol Character string for symbol you would like to process
#'
#'   Value will be used to name the output .RData file
#'
#' @param opt_path Character string of path to iVolatility files
#'
#'   When files are downloaded from iVolatility they are limited in size to 50Mb.
#'   Place all the files in the "opt_path" folder under your working directory.
#'
#' @param iv_file Character string of volatility file for symbol chosen
#'
#'   IVRank data from \href{http://www.cboe.com/micro/equityvix/introduction.aspx}{http://www.cboe.com/micro/equityvix/introduction.aspx}
#'   make sure to remove the disclaimer at the top of the file from this site.
#'
#'   IV can also be calculated outside this process and used if the file format
#'   is the same.
#'
#' @return \code{tidy_options} returns tidy options chain data with
#'  (rsi_14, iv_rank_252, and iv_rank_90) added.
#'
#'  Output can then be used in \code{options.shiny} and \code{options.studies}
#'  for backtesting.
#'
#' @export
#'
#' @examples
#' complete.data <- tidy_options("SPY", "data/raw", "vx.xle.daily.prices.RData")

tidy_options <- function(symbol, opt_path, iv_file) {
  files <- list.files(path = opt_path,
                      pattern = ".csv", full.names = TRUE)

  rbind_csv <- function(file_name) {
    fread(file_name)
  }

  dat <- map(files, rbind_csv)
  raw_data <- bind_rows(dat)
  load(iv_file)

  # Dates the market was closed and can't be used in studies
  closed_dates <- fread("data/market_closed.csv")
  closed_dates$closed_dates <- as.Date(closed_dates$closed_dates)

  # This removes (exchange, style, stock price for IV, and *)
  raw_data <- raw_data %>%
    select(-c(2, 9, 16, 17)) %>%
    mutate(date = as.Date(date, "%m/%d/%y"),
           expiration = as.Date(expiration, "%m/%d/%y"))

  names(raw_data) <- c("symbol", "date", "price", "option", "expiration",
                       "strike", "call.put", "ask", "bid", "mid.price",
                       "iv", "volume", "open.interest", "delta", "vega",
                       "gamma", "theta", "rho")

  # Third Friday expiration dates
  monthy_exp_dates <-
    third_friday(min(year(raw_data$date)), max(year(raw_data$date)))

  # Remove rows for dates that the market was closed
  # For some reason iVolatility sometimes includes these
  raw_data <- raw_data %>%
    mutate(exp_day = weekdays(expiration, abbreviate = FALSE),
           expiration = as.Date(ifelse(exp_day == "Saturday",
                                       expiration - 1,
                                       expiration), origin = "1970-01-01"),
           expiration = as.Date(ifelse(expiration %in% closed_dates,
                                       expiration - 1,
                                       expiration), origin = "1970-01-01"),
           dte = as.integer(expiration - date),
           exp_type = ifelse(is.element(expiration, monthy_exp_dates),
                             "Monthly", "Weekly")) %>%
    filter(!date %in% closed_dates) %>%
    select(-exp_day)

  # Calculate rsi_14 day for use in studies
  # Gather all the unique trading dates to calculate study values
  unique_dates <- raw_data %>%
    distinct(date, .keep_all = TRUE) %>%
    mutate(rsi_14 = RSI(price, 14)) %>%
    select(date, rsi_14)

  raw_data <- left_join(raw_data, unique_dates, by = "date")

  # Remove market closed dates from IV data
  iv.raw.data <- iv.raw.data %>%
    mutate(date = as.Date(Date, "%m/%d/%Y")) %>%
    filter(!date %in% closed_dates) %>%
    mutate(iv_rank_252 = round(100 * runPercentRank(Close, n = 252,
                                                    cumulative = FALSE,
                                                    exact.multiplier = 1),
                               digits = 0),
           iv_rank_90 = round(100 * runPercentRank(Close, n = 90,
                                                   cumulative = FALSE,
                                                   exact.multiplier = 1),
                              digits = 0)) %>%
    select(date, iv_rank_252, iv_rank_90)

  # Join the data together adding iv_rank
  raw_data <- left_join(raw_data, iv.raw.data, by = "date")

  complete.data <- raw_data %>%
    filter(rsi_14 != "NA",
           iv_rank_252 != "NA")

  #complete.data

  # Export to .rda file for package
  #save(complete.data, file = paste0(symbol, ".options.RData"))
}
