from jpype import *
import numpy as np
import sys
# Our python data file readers are a bit of a hack, python users will do better on this:
sys.path.append("/Users/simongimmini/forks/jidt/demos/python")
import readFloatsFile
from pprint import pprint
import pandas as pd
import re
import os
from os import path as osp, stat
from tqdm import tqdm
import matplotlib.pyplot as plt
from statsmodels.graphics.tsaplots import plot_acf

# function to read in a file and make it useable for R
def make_locals_useable(locals_file, output_file):

    # output df where columns will be sensor pairs and rows values
    output_df = pd.DataFrame()
    with open(locals_file, 'r') as f:
        # read in file
        lines = f.readlines()
        print(len(lines))
        for i, l in tqdm(enumerate(lines)):
            if i == 0:
                continue
            else:
                # split line by , 
                line = l.split(",")
                # only look for tl 0 
                if line[5] != "0":
                    continue
                # capture everything between " " and save in variable local_values
                local_values = re.findall(r'"([^"]*)"', l)[0]
                # remove ' from local_values
                local_values = local_values.replace("'", "")
                # split local_values at , and save in variable local_values
                local_values = local_values.split(",")
                # make float
                local_values = [float(i) for i in local_values]
                # for each line combine Sensor1 and Sensor2 to Sensors
                sensor_pair = line[3] + "_" + line[4]

                # create temp df with sensor_pair as column name and local_values as values
                temp_df = pd.DataFrame({sensor_pair: local_values})

                # concatenate temp_df to output_df
                output_df = pd.concat([output_df, temp_df], axis=1)

    # save output df to csv
    output_df.to_csv(output_file, index=False)



# plot autocorrelation function for one column of a file that is read in as a pandas df
def plot_acf_for_file(file_path, lags=100):
    # print all column names
    df = pd.read_csv(file_path, sep=";")
    print(df.columns)

    # let the user choose the column to plot
    column = input("Please enter the column name to plot the acf for: ")

    df = pd.read_csv(file_path)
    plot_acf(df[column], lags=lags)
    plt.show() 

def get_year_month_day(file):
    try:    
        # get day, month and year from file name in pattern dd-mm-yyyy with regex
        day, month, year = re.findall(r'\d+', file.split("/")[-1])
    # except value error 
    except ValueError:
        try:
            # get month and year from file name in pattern mm-yyyy with regex
            month, year = re.findall(r'\d+', file.split("/")[-1])
            day = np.nan
        except ValueError:
            # get year from file name in pattern yyyy with regex
            year = re.findall(r'\d+', file.split("/")[-1])[0]
            month = np.nan
            # dict of weekday names to numbers 
            # this is for having a structure for a better analysis
            weekdays = {"monday": 1, "tuesday": 2, "wednesday": 3, "thursday": 4, "friday": 5, "saturday": 6, "sunday": 7}

            # check if file name contains a weekday
            for weekday in weekdays:
                if weekday in file:
                    day = weekdays[weekday]
                    break
                else:
                    day = np.nan

    return year, month, day


def set_split_length(month):
    # if month is 1, 3, 5, 7, 8, 10, 12
    if month in [1, 3, 5, 7, 8, 10, 12]:
        split_length = 31
    # if month is 4, 6, 9, 11
    elif month in [4, 6, 9, 11]:
        split_length = 30
    # if month is 2
    elif month == 2:
        # I removed 29th in all datasets
        split_length = 28

    return split_length

# function to search for the best parameters for all columns and save them in a csv
def search_for_best_parameters(file, outfile_name, measure):
    tqdm.write("Searching for best parameters for {}".format(file))    

    # pandas df to save the best parameters with column names for different parameters, depending on "measure"
    # for AIS: k, tau 
    # for TE: k, ktau, l, ltau
    if measure == "AIS":
        best_parameters_df = pd.DataFrame(columns=["column", "k", "ktau"])
    elif measure == "TE":
        best_parameters_df = pd.DataFrame(columns=["column", "k", "ktau", "l", "ltau"])

    # read first line of file to get column names
    with open(file, 'r') as f:
        column_names = f.readline().split(",")
        # remove any non digit characters from column names
        column_names = [re.sub(r'\D', '', i) for i in column_names]

    dataRaw = readFloatsFile.readFloatsFile(file)

    data = np.array(dataRaw)
    # 1. Construct the calculator:
    if measure == "AIS":
        calcClass = JPackage("infodynamics.measures.continuous.kraskov").ActiveInfoStorageCalculatorKraskov
    elif measure == "TE":
        calcClass = JPackage("infodynamics.measures.continuous.kraskov").TransferEntropyCalculatorKraskov

    calc = calcClass()

    if measure == "TE":
        calc.setProperty("ALG_NUM", "2")

    calc.setProperty("DYN_CORR_EXCL", str(29))
    calc.setProperty("AUTO_EMBED_METHOD", "MAX_CORR_AIS")
    calc.setProperty("AUTO_EMBED_K_SEARCH_MAX", "10")
    calc.setProperty("AUTO_EMBED_TAU_SEARCH_MAX", "10")

    for d in tqdm(range(data.shape[1]), position=0, leave=False):
        for s in tqdm(range(data.shape[1]), position=1, leave=False):
            # if measure is AIS and s is not 0, skip 
            if measure == "AIS" and s != 0:
                continue
            if d == s:
                continue

            calc.initialise()

            source = JArray(JDouble, 1)(data[:, s].tolist())
            destination = JArray(JDouble, 1)(data[:, d].tolist())

            if measure == "AIS":
                calc.setObservations(destination)
                # get properties k_HISTORY, and TAU
                k = int(''.join(map(str, calc.getProperty("k_HISTORY"))))
                tau = int(''.join(map(str, calc.getProperty("TAU"))))
                # save k and tau in best_parameters_df with pd concat
                best_parameters_df = pd.concat([best_parameters_df, pd.DataFrame({"column": [column_names[d]], "k": [k], "ktau": [tau]})], axis=0)

            else:
                calc.setObservations(source, destination)
                # get properties k_HISTORY, k_TAU, l_HISTORY, l_TAU
                k = int(''.join(map(str, calc.getProperty("k_HISTORY"))))
                ktau = int(''.join(map(str, calc.getProperty("k_TAU"))))
                l = int(''.join(map(str, calc.getProperty("l_HISTORY"))))
                ltau = int(''.join(map(str, calc.getProperty("l_TAU"))))
                # save k, ktau, l, ltau in best_parameters_df with pd concat
                best_parameters_df = pd.concat([best_parameters_df, pd.DataFrame({"column": [column_names[d]], "k": [k], "ktau": [ktau], "l": [l], "ltau": [ltau]})], axis=0)


    print(best_parameters_df)
    # print min, max and mean of all columns except column
    print("k: min: {}, max: {}, mean: {}".format(best_parameters_df.k.min(), best_parameters_df.k.max(), best_parameters_df.k.mean()))
    print("ktau: min: {}, max: {}, mean: {}".format(best_parameters_df.ktau.min(), best_parameters_df.ktau.max(), best_parameters_df.ktau.mean()))
    try:
        print("l: min: {}, max: {}, mean: {}".format(best_parameters_df.l.min(), best_parameters_df.l.max(), best_parameters_df.l.mean()))
        print("ltau: min: {}, max: {}, mean: {}".format(best_parameters_df.ltau.min(), best_parameters_df.ltau.max(), best_parameters_df.ltau.mean()))
    except:
        pass
    # print(best_parameters_df.drop("column", axis=1).describe())

    # save best_parameters_df to csv
    best_parameters_df.to_csv(outfile_name, index=False)




# function to calculate the mutual information 
def mutal_information_calculation(file_path, outfile_name, verbose=False, stat_signif=False, time_lag_max=10, dyn_corr_excl=0, split_observations=False, split_length=None, compute_locals=False):

    tqdm.write("Calculating mutual information")
    # array with all files in file_root with os.path
    if ".csv" in file_path:
        files = [file_path]
    else:
        files = [osp.join(file_path, f) for f in os.listdir(file_path) if osp.isfile(osp.join(file_path, f))]


    # debug:
    #files = [os.listdir(file_root)[:2]]

    # pandas df with columns Year, Month, Day, Sensor1, Sensor2, Time_lag, MI and Stat_sig
    df = pd.DataFrame(columns=["Year", "Month", "Day", "Sensor1", "Sensor2", "Time_lag", "MI", "Stat_Sig"])

    if compute_locals:
        df_local = pd.DataFrame(columns=["Year", "Month", "Day", "Sensor1", "Sensor2", "Time_lag", "MI", "Stat_Sig", "Local_MI"])

    for file in tqdm(files, position=0, desc="Processing files"):

        #file_path = osp.join(file_root, file)
        # print("----------------------------------")
        tqdm.write("Processing file: \"" + file + "\"")

        year, month, day = get_year_month_day(file)

        if verbose:
            print("Year: " + str(year) + ", Month: " + str(month) + ", Day: " + str(day))

        # read first line of file to get column names
        with open(file, 'r') as f:
            column_names = f.readline().split(',')
            # remove any non digit characters from column names
            column_names = [re.sub(r'\D', '', column_name) for column_name in column_names]

        # 0. Load/prepare the data:
        dataRaw = readFloatsFile.readFloatsFile(file)

        # print column names if verbose
        if verbose:
            print("Column names: " + str(column_names))

        # As numpy array:
        data = np.array(dataRaw)
        # 1. Construct the calculator:
        calcClass = JPackage("infodynamics.measures.continuous.kraskov").MutualInfoCalculatorMultiVariateKraskov1
        calc = calcClass()

        if not split_observations:
            calc.setProperty("DYN_CORR_EXCL", str(dyn_corr_excl))

        for time_lag in tqdm(range(0, time_lag_max+1), position=1, leave=False, desc="Time lag"):
            # 2. Set any properties to non-default values:
            calc.setProperty("TIME_DIFF", str(time_lag))

            # Compute for all pairs:
            for s in tqdm(range(data.shape[1]), position=2, leave=False, desc="Sensor 1"):
                for d in tqdm(range(data.shape[1]), position=3, leave=False, desc="Sensor 2"):
                    # For each source-dest pair:
                    if (s == d):
                        continue

                    # 3. Initialise the calculator for (re-)use:
                    calc.initialise()

                    if split_observations:
                        if time_lag == 0:
                            source = JArray(JDouble, 1)(data[:, s].tolist())
                            destination = JArray(JDouble, 1)(data[:, d].tolist())
                            calc.setObservations(source, destination)
                        else:
                            calc.startAddObservations()

                            if split_length == 31:
                                split_length = set_split_length(month=month)

                            for i in range(0, data.shape[0], split_length):
                                source = JArray(JDouble, 1)(data[i:i+split_length, s].tolist())
                                destination = JArray(JDouble, 1)(data[i:i+split_length, d].tolist())
                                calc.addObservations(source, destination)

                            # 4. Finalise adding observations:
                            calc.finaliseAddObservations()

                    else:
                        source = JArray(JDouble, 1)(data[:, s].tolist())
                        destination = JArray(JDouble, 1)(data[:, d].tolist())
                        calc.setObservations(source, destination)


                    # 4. Supply the sample data:
                    calc.setObservations(source, destination)

                    # 5. Compute the estimate:
                    if compute_locals:
                        locals = np.array(calc.computeLocalOfPreviousObservations())
                        # convert locals to a string with 4 decimal places and each value seperated by a comma
                        locals = ",".join([f"{local:.4f}" for local in locals])
                    result = calc.computeAverageLocalOfObservations()

                    if stat_signif:
                        # 6. Compute the (statistical significance via) null distribution empirically (e.g. with 100 permutations):
                        measDist = calc.computeSignificance(100)
                        nulldist = measDist.getMeanOfDistribution()
                        std = measDist.getStdOfDistribution()
                        p_value = measDist.pValue
                    else: 
                        p_value = np.nan

                    # save results in df with pd.concat
                    df = pd.concat([df, pd.DataFrame([[year, month, day, column_names[s], column_names[d], time_lag, result, p_value]], columns=["Year", "Month", "Day", "Sensor1", "Sensor2", "Time_lag", "MI", "Stat_Sig"])], ignore_index=True)
                    if compute_locals:
                        df_local = pd.concat([df_local, pd.DataFrame([[year, month, day, column_names[s], column_names[d], time_lag, result, p_value, locals]], columns=["Year", "Month", "Day", "Sensor1", "Sensor2", "Time_lag", "MI", "Stat_Sig", "Local_MI"])], ignore_index=True)
 
                    # print result for each sensor pair with 4 decimal places, nulldist, std, p_value and time lag using f-string
                    if verbose:
                        if stat_signif:
                            tqdm.write(f"MI({column_names[s]} -> {column_names[d]}) = {result:.4f} nulldist = {nulldist:.4f} std = {std:.4f} p_value = {p_value:.4f} time lag = {time_lag}")
                        else:
                            print(f"MI_Kraskov for sensor {column_names[s]} to sensor {column_names[d]} = {result:.4f} nats, time lag: {time_lag}")

                    
        # save df to csv
        if stat_signif:
            if outfile_name.endswith("_stat_sig.csv"):
                df.to_csv(outfile_name, index=False)
                if compute_locals:
                    df_local.to_csv(outfile_name_locals, index=False)
            else:
                if compute_locals:
                    outfile_name_locals = outfile_name.split(".")[0] + "_locals_stat_sig.csv"
                    df_local.to_csv(outfile_name_locals, index=False)
                outfile_name = outfile_name.split(".")[0] + "_stat_sig.csv"
                df.to_csv(outfile_name, index=False)

        else:
            if compute_locals:
                outfile_name_locals = outfile_name.split(".")[0] + "_locals.csv"
                df_local.to_csv(outfile_name_locals, index=False)
            df.to_csv(outfile_name, index=False)



# function to calculate the active information storage
def active_information_storage_calculation(file_path, outfile_name, verbose=False, stat_signif=False, dyn_corr_excl=0, split_observations=False, split_length=None):

    tqdm.write("Calculating active information storage")
    # array with all files in file_root with os.path
    if ".csv" in file_path:
        files = [file_path]
    else:
        files = [osp.join(file_path, f) for f in os.listdir(file_path) if osp.isfile(osp.join(file_path, f))]

   
    # debug:
    #files = [os.listdir(file_root)[:2]]
    
    # pandas df with columns Year, Month, Day, Sensor, AIS and Stat_sig
    df = pd.DataFrame(columns=["Year", "Month", "Day", "Sensor", "AIS", "Stat_Sig"])
    
    for file in tqdm(files, position=0, desc="Processing files"):
    
        tqdm.write("Processing file: \"" + file + "\"")
    
        year, month, day = get_year_month_day(file)

        if verbose:
            print("Year: " + str(year) + ", Month: " + str(month) + ", Day: " + str(day))

        # read first line of file to get column names
        with open(file, 'r') as f:
            column_names = f.readline().split(',')
            # remove any non digit characters from column names
            column_names = [re.sub(r'\D', '', column_name) for column_name in column_names]
    
        # 0. Load/prepare the data:
        dataRaw = readFloatsFile.readFloatsFile(file)
    
        # print column names if verbose
        if verbose:
            print("Column names: " + str(column_names))
    
        # As numpy array:
        data = np.array(dataRaw)
        # 1. Construct the calculator:
        calcClass = JPackage("infodynamics.measures.continuous.kraskov").ActiveInfoStorageCalculatorKraskov
        calc = calcClass()
    
        # 2. Set any properties to non-default values:
        calc.setProperty("k_History", "2")
        calc.setProperty("TAU", "5")
                
        # Compute for all columns:
        for v in tqdm(range(data.shape[1]), position=2, leave=False, desc="Sensor 1"):

            # set properties
            # FIXME: Addition of multiple observation sets is not currently supported with property DYN_CORR_EXCL set
            if not split_observations:
                calc.setProperty("DYN_CORR_EXCL", str(dyn_corr_excl)) 
                calc.setProperty("AUTO_EMBED_METHOD", "MAX_CORR_AIS")
                calc.setProperty("AUTO_EMBED_K_SEARCH_MAX", "10")
                calc.setProperty("AUTO_EMBED_TAU_SEARCH_MAX", "10")

            # 3. Initialise the calculator for (re-)use:
            calc.initialise()

            if split_observations:
                calc.startAddObservations()

                if split_length == 31:
                    split_length = set_split_length(month=month)                    

                # split every column to oberservations of length 24 for every day
                for i in range(0, data.shape[0], split_length):
                    observations = JArray(JDouble, 1)(data[i:i+split_length, v].tolist())
                    calc.addObservations(observations)

                # 4. Finalise adding observations:
                calc.finaliseAddObservations()

            else: 
                variable = JArray(JDouble, 1)(data[:, v].tolist())
    
                # 4. Supply the sample data:
                calc.setObservations(variable)

            result = calc.computeAverageLocalOfObservations()
            if stat_signif:
                # 6. Compute the (statistical significance via) null distribution empirically (e.g. with 100 permutations):
                measDist = calc.computeSignificance(100)
                nulldist = measDist.getMeanOfDistribution()
                std = measDist.getStdOfDistribution()
                p_value = measDist.pValue
            else: 
                p_value = np.nan

            # save results in df with pd.concat
            df = pd.concat([df, pd.DataFrame([[year, month, day, column_names[v], result, p_value]], columns=["Year", "Month", "Day", "Sensor", "AIS", "Stat_Sig"])], ignore_index=True)

            # print result for each sensor pair with 4 decimal places, nulldist, std, p_value and time lag using f-string
            if verbose:
                if stat_signif:
                    tqdm.write(f"AIS({column_names[v]}) = {result:.4f} nulldist = {nulldist:.4f} std = {std:.4f} p_value = {p_value:.4f}")
                else:
                    print(f"AIS_Kraskov for sensor {column_names[v]} = {result:.4f} nats")

    
        # save df to csv every file iteration
        if stat_signif:
            if outfile_name.endswith("_stat_sig.csv"):
                df.to_csv(outfile_name, index=False)
            else:
                outfile_name = outfile_name.split(".")[0] + "_stat_sig.csv"
                df.to_csv(outfile_name, index=False)
        else:
            df.to_csv(outfile_name, index=False)


# function to calculate the transfer entropy for all sensor pairs
def transfer_entropy_calculation(file_path, outfile_name, verbose=False, stat_signif=False, time_lag_max=10, dyn_corr_excl=0, split_observations=False, split_length=None, compute_locals=False):

    tqdm.write(f"Calculating transfer entropy for {file_path}")
    # array with all files in file_root with os.path
    if ".csv" in file_path:
        files = [file_path]
    else:
        files = [osp.join(file_path, f) for f in os.listdir(file_path) if osp.isfile(osp.join(file_path, f))]


    # pandas df with columns Year, Month, Day, Sensor1, Sensor2, Time_lag, TE and Stat_sig
    df = pd.DataFrame(columns=["Year", "Month", "Day", "Sensor1", "Sensor2", "Time_lag", "TE", "Stat_sig"])

    if compute_locals:
        # pandas df to save local values of transfer entropy with same columns as df and additional column Local_TE
        df_local = pd.DataFrame(columns=["Year", "Month", "Day", "Sensor1", "Sensor2", "Time_lag", "TE", "Stat_sig", "Local_TE"])

    for file in tqdm(files, position=0, desc="Processing files"):

        tqdm.write("Processing file: \"" + file + "\"")

        year, month, day = get_year_month_day(file)

        # read first line of file to get column names
        with open(file, 'r') as f:
            column_names = f.readline().split(',')
            # remove any non digit characters from column names
            column_names = [re.sub(r'\D', '', column_name) for column_name in column_names]

        # 0. Load/prepare the data:
        dataRaw = readFloatsFile.readFloatsFile(file)

        # print column names if verbose
        if verbose:
            print("Column names: " + str(column_names))

        # As numpy array:
        data = np.array(dataRaw)
        
        # 1. Construct the calculator:
        calcClass = JPackage("infodynamics.measures.continuous.kraskov").TransferEntropyCalculatorKraskov
        calc = calcClass()
        # 2. Set any properties to non-default values:
        calc.setProperty("k_HISTORY", "3")
        calc.setProperty("k_TAU", "3")
        calc.setProperty("l_HISTORY", "3")
        calc.setProperty("l_TAU", "3")

        if not split_observations:
            calc.setProperty("DYN_CORR_EXCL", str(dyn_corr_excl))
            # calc.setProperty("AUTO_EMBED_METHOD", "MAX_CORR_AIS")
            # calc.setProperty("AUTO_EMBED_K_SEARCH_MAX", "10")
            # calc.setProperty("AUTO_EMBED_TAU_SEARCH_MAX", "10")

        for time_lag in tqdm(range(1, time_lag_max+1), position=1, leave=False, desc="Processing time lags"):
            calc.setProperty("DELAY", str(time_lag))
            # Compute for all pairs:
            for d in tqdm(range(data.shape[1]), position=2, leave=False, desc="Processing targets"):
                for s in tqdm(range(data.shape[1]), position=3, leave=False, desc="Processing sources"):
                    # For each source-dest pair:
                    if (s == d):
                        continue

                    # 3. Initialise the calculator for (re-)use:
                    calc.initialise()

                    if split_observations:
                        calc.startAddObservations()

                        if split_length == 31:
                            split_length = set_split_length(month=month)                    

                        # split every column to oberservations 
                        for i in range(0, data.shape[0], split_length):
                            source = JArray(JDouble, 1)(data[i:i+split_length, s].tolist())
                            destination = JArray(JDouble, 1)(data[i:i+split_length, d].tolist())
                            calc.addObservations(source, destination)

                        # 4. Finalise adding observations:
                        calc.finaliseAddObservations()
                    
                    else:
                        source = JArray(JDouble, 1)(data[:, s].tolist())
                        destination = JArray(JDouble, 1)(data[:, d].tolist())
                        # 4. Supply the sample data:
                        calc.setObservations(source, destination)

                    # 5. Compute the estimate:
                    if compute_locals:
                        locals = np.array(calc.computeLocalOfPreviousObservations())
                        # convert locals to a string with 4 decimal places and each value seperated by a comma
                        locals = ",".join([f"{local:.4f}" for local in locals])
                    result = calc.computeAverageLocalOfObservations()

                    # plot source and destination as time series and locals as x 
                    # normalize source and destination
                    # source = (source - np.mean(source)) / np.std(source)
                    # destination = (destination - np.mean(destination)) / np.std(destination)
                    # plt.plot(source)
                    # plt.plot(destination)
                    # # plot locals as x markers
                    # plt.plot(locals, 'x')
                    # plt.show()
                    # print(locals)
                    # print(type(locals))
                    # exit()

                    if stat_signif:
                        # 6. Compute the (statistical significance via) null distribution empirically (e.g. with 100 permutations):
                        measDist = calc.computeSignificance(100)
                        nulldist = measDist.getMeanOfDistribution()
                        std = measDist.getStdOfDistribution()
                        p_value = measDist.pValue
                    else:
                        p_value = np.nan

                    # save results in df with pd.concat
                    df = pd.concat([df, pd.DataFrame([[year, month, day, column_names[s], column_names[d], time_lag, result, p_value]], columns=["Year", "Month", "Day", "Sensor1", "Sensor2", "Time_lag", "TE", "Stat_sig"])], ignore_index=True)
                    if compute_locals:
                        df_local = pd.concat([df_local, pd.DataFrame([[year, month, day, column_names[s], column_names[d], time_lag, result, p_value, locals]], columns=["Year", "Month", "Day", "Sensor1", "Sensor2", "Time_lag", "TE", "Stat_sig", "Local_TE"])], ignore_index=True)

                    # print result for each sensor pair with 4 decimal places, null distribution, std, p-value and time lag using f-string
                    if verbose:
                        if stat_signif:
                            print(f"TE_Kraskov for sensor {column_names[s]} to sensor {column_names[d]} = {result:.4f} nats, null distribution: {nulldist}, std: {std}, p-value: {p_value}, time lag: {time_lag}")
                        else:
                            print(f"TE_Kraskov for sensor {column_names[s]} to sensor {column_names[d]} = {result:.4f} nats, time lag: {time_lag}")

            if stat_signif:
                if outfile_name.endswith("_stat_sig.csv"):
                    df.to_csv(outfile_name, index=False)
                    if compute_locals:
                        df_local.to_csv(outfile_name_locals, index=False)
                else:
                    if compute_locals:
                        outfile_name_locals = outfile_name.split(".")[0] + "_locals_stat_sig.csv"
                        df_local.to_csv(outfile_name_locals, index=False)
                    outfile_name = outfile_name.split(".")[0] + "_stat_sig.csv"
                    df.to_csv(outfile_name, index=False)

            else:
                if compute_locals:
                    outfile_name_locals = outfile_name.split(".")[0] + "_locals.csv"
                    df_local.to_csv(outfile_name_locals, index=False)
                df.to_csv(outfile_name, index=False)


  

# main function
def main():

    # Add JIDT jar library to the path
    jarLocation = "/Users/simongimmini/forks/jidt/infodynamics.jar"

    # Start the JVM (add the "-Xmx" option with say 1024M if you get crashes due to not enough memory space)
    startJVM(getDefaultJVMPath(), "-ea", "-Djava.class.path=" + jarLocation)

    # DAY / WEEK
    # day_file = "data/one_week/datetime_sensor_id_week-11-2018.csv" 
    day_file = "data/one_week/days/datetime_sensor_id_12-11-2018.csv" 
    # plot_acf_for_file(day_file, 23)
    # active_information_storage_calculation(day_file, outfile_name="week_hourly_AIS.csv", verbose=False, stat_signif=True, dyn_corr_excl=25)
    # mutal_information_calculation(day_file, outfile_name="week_hourly_MI_TL24.csv", verbose=False, stat_signif=False, time_lag_max=24, dyn_corr_excl=25)
    # FIXME transfer_entropy_calculation(day_file, outfile_name="day_hourly_TE_TL5.csv", verbose=False, stat_signif=False, time_lag_max=5, dyn_corr_excl=0)

    # MONTH
    month_file = "data/one_month/datetime_sensor_id_eight_fifteen_2-2018.csv"
    # plot_acf_for_file(month_file, 100)
    # active_information_storage_calculation(month_file, outfile_name="month_hourly_AIS.csv", verbose=False, stat_signif=True, dyn_corr_excl=29)
    # mutal_information_calculation(month_file, outfile_name="month_hourly_MI_TL24.csv", verbose=False, stat_signif=False, time_lag_max=24, dyn_corr_excl=29)
    # transfer_entropy_calculation(month_file, outfile_name="feb18_sensor-8-15_hourly_TE_TL5.csv", verbose=False, stat_signif=True, time_lag_max=5, dyn_corr_excl=29)


    # YEAR
    year_file = "data/refactored_years_hourly/datetime_sensor_id_refactor_2018.csv"
    # plot_acf_for_file(year_file, 100) # -> 24 for month and year
    # active_information_storage_calculation(year_file, outfile_name="year_hourly_AIS.csv", verbose=False, stat_signif=True, dyn_corr_excl=29)
    # mutal_information_calculation(year_file, outfile_name="year2018_sensors1-2_hourly_MI_TL1.csv", verbose=False, stat_signif=False, time_lag_max=1, dyn_corr_excl=29, compute_locals=True)
    transfer_entropy_calculation(year_file, outfile_name="year18_hourly_TE_TL5.csv", verbose=False, stat_signif=False, time_lag_max=1, dyn_corr_excl=29)

    # WEEKDAYS
    weekday_file = "data/weekdays"#/datetime_sensor_id_monday-2018.csv"
    # plot_acf_for_file(weekday_file, 100) # -> 29
    # active_information_storage_calculation(weekday_file, outfile_name="weekday_hourly_AIS.csv", verbose=False, stat_signif=True, dyn_corr_excl=29, split_observations=True, split_length=24)
    # mutal_information_calculation(weekday_file, outfile_name="weekday_hourly_MI_TL5.csv", verbose=False, stat_signif=True, time_lag_max=5, dyn_corr_excl=29, split_observations=True, split_length=24)
    transfer_entropy_calculation(weekday_file, outfile_name="weekday_hourly_TE_TL5.csv", verbose=False, stat_signif=True, time_lag_max=5, dyn_corr_excl=29, split_observations=True, split_length=24)

    # MONTHS - this is different from MONTH, as here I have ensured to have the same sensors for all months
    months_file = "data/one_year/"
    # plot_acf_for_file(osp.join(months_file, os.listdir(months_file)[0]), 100) # -> 29
    # active_information_storage_calculation(months_file, outfile_name="months_hourly_AIS.csv", verbose=False, stat_signif=True, dyn_corr_excl=29)
    # mutal_information_calculation(months_file, outfile_name="months_hourly_MI_TL5.csv", verbose=False, stat_signif=False, time_lag_max=5, dyn_corr_excl=29)
    # transfer_entropy_calculation(months_file, outfile_name="months_hourly_TE_TL5.csv", verbose=False, stat_signif=False, time_lag_max=5, dyn_corr_excl=29)

    # YEARS - years 2019 - 2021
    years_file = "data/three_years/datetime_sensor_id_1921.csv"
    # plot_acf_for_file(osp.join(years_file, os.listdir(years_file)[0]), 100) # -> 29
    # plot_acf_for_file(years_file, 100) # -> 31
    # active_information_storage_calculation(years_file, outfile_name="years1921_hourly_AIS.csv", verbose=False, stat_signif=True, dyn_corr_excl=31, split_observations=False)
    # mutal_information_calculation(years_file, outfile_name="years1921_hourly_MI_TL5.csv", verbose=False, stat_signif=False, time_lag_max=5, dyn_corr_excl=31)
    # transfer_entropy_calculation(years_file, outfile_name="years1921_hourly_TE_TL5.csv", verbose=False, stat_signif=False, time_lag_max=5, dyn_corr_excl=29, split_observations=False, split_length=31)

    # make locals useable for R
    # make_locals_useable("year_hourly_MI_TL5_locals.csv", "local_MI_2018_TL0.csv")

    # search for best parameters
    # search_for_best_parameters("data/one_year/datetime_sensor_id_6-2018.csv", "TE_search_alg2.csv", "TE")

            
# main
if __name__ == "__main__":
    main()