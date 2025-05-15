function analyse_speakers(JSON_INFILE,varargin)

%% Analyse speakers by plotting a ranking of means and CIs of `diff` scores for each speaker.

CI_ALPHA = 0.10;                % -- alpha for bootstrapped CI calculation
GROUPING_VARS = {'speaker'};    % -- default grouping variables for rowfun
MIN_ENTRIES = 10;               % -- minimum number of speeches a speaker must have to be included in the analysis
MSIZE = 70;                     % -- marker size
MJITTER = 2;                  % -- marker jitter
KS_DENSITY_BANDWIDTH = 1000000; % -- bandwidth for ksdensity estimation
ELECTIONS_CSV = 'federal_elections.csv';    % -- csv file containing dates of federal elections
PM_CSV = 'prime_minister_by_year.csv';      % -- csv file containing years of prime minister in office
PM_TERMS = 'prime_minister_terms.csv';      % -- csv file containing term dates of prime minister in office (name,start_date,end_date)

% Ingest json, convert to table
c = fileread(JSON_INFILE);
s = jsondecode(c);
t = struct2table(s);
t.year = year(datetime(t.date));
t.month = month(datetime(t.date));
t.quarter = quarter(datetime(t.date));

%% Process varargin as name-value pairs
do_group_by_speaker_year = false;
do_group_by_speaker_month = false;
do_output_summary_table = false;
do_group_by_speaker_dynamic = false;
do_group_by_speaker_quarter = false;
do_group_by_speaker_affiliation = false;
do_color_by_party = false;
show_error_bars = false;
for i = 1:2:length(varargin)
    name = varargin{i};
    value = varargin{i+1};
    switch name
        case 'CI_ALPHA'
            CI_ALPHA = value;
        case 'group_by_speaker_dynamic'
            do_group_by_speaker_dynamic = value;
        case 'group_by_speaker_year'
            do_group_by_speaker_year = value;
        case 'group_by_speaker_month'
            do_group_by_speaker_month = value;
        case 'group_by_speaker_quarter'
            do_group_by_speaker_quarter = value;
        case 'group_by_speaker_year'
            do_group_by_speaker_year = value;
        case 'group_by_speaker_affiliation'
            do_group_by_speaker_affiliation = value;
        case 'output_summary_table'
            do_output_summary_table = value;
        case 'color_by_party'
            do_color_by_party = value;
        case 'set_min_entries'
            MIN_ENTRIES = value;
        case 'show_error_bars'
            show_error_bars = value;
    end
end

if do_group_by_speaker_month | do_group_by_speaker_year | do_group_by_speaker_quarter | do_group_by_speaker_affiliation
    if do_group_by_speaker_year
        try
            GROUPING_VARS = {'speaker', 'affiliation', 'year'};
        catch
            GROUPING_VARS = {'speaker', 'year'};
        end
    elseif do_group_by_speaker_month
        GROUPING_VARS = {'speaker', 'affiliation', 'year', 'month'};
    elseif do_group_by_speaker_quarter
        GROUPING_VARS = {'speaker', 'affiliation', 'year', 'quarter'};
    elseif do_group_by_speaker_affiliation
        GROUPING_VARS = {'speaker', 'affiliation'};
    end

    % Apply rowfun, grouping by speaker to get mean and CI of `diff` scores
    S = rowfun(@(x) my_mean_ci(x, CI_ALPHA, MIN_ENTRIES), t, ...
        'GroupingVariable', GROUPING_VARS, ...
        'InputVariables', 'diff',...
        'OutputVariableNames', {'mean' 'CI' 'median'});

    % Create plot_date
    if do_group_by_speaker_month
        S.plot_date = datetime(S.year, S.month, 1);
    elseif do_group_by_speaker_year
        S.plot_date = datetime(S.year, 1, 1);
    elseif do_group_by_speaker_quarter
        S.plot_date = datetime(S.year, S.quarter*3-2, 1);
    end

elseif do_group_by_speaker_dynamic
    % -- bin dynamically based on identifying binning edges from ksdensity estimation with findpeaks
    % .. first, get the ksdensity estimate
    t.dt = datetime(t.date);
    t.posix = posixtime(t.dt);
    [f,xi] = ksdensity(t.posix, ...
        'bandwidth', KS_DENSITY_BANDWIDTH);
    % .. find troughs
    [pks,locs] = findpeaks(-f, xi);
    % .. add min and max to locs
    locs = [min(t.posix)-1 locs max(t.posix)+1];
    % .. iterate through troughs, create record_date entry in table as mean of locs(i) and locs(i+1)
    n = numel(locs);
    record_date = NaT(height(t),1);
    for i = 1:n-1
        ix = t.posix >= locs(i) & t.posix < locs(i+1);
        centre_dt_posix = round(mean(locs(i:i+1)));
        record_date(ix) = datetime(centre_dt_posix, 'ConvertFrom', 'posixtime');
    end
    t.record_date = datetime(record_date, 'Format', 'dd-MMM-yyyy');
    t.year = year(t.record_date);
    t.month = month(t.record_date);

    % .. now apply rowfun, grouping by speaker to get mean and CI of `diff` scores
    S = rowfun(@(x) my_mean_ci(x, CI_ALPHA, MIN_ENTRIES), t, ...
        'GroupingVariable', {'speaker', 'record_date' 'year' 'month'}, ...
        'InputVariables', 'diff',...
        'OutputVariableNames', {'mean' 'CI' 'median'});

    % .. additionall output the bin edges from `locs`, in date format
    bin_start = datetime(locs(1:end-1), 'ConvertFrom', 'posixtime', 'Format', 'dd-MMM-yyyy');
    bin_end = datetime(locs(2:end), 'ConvertFrom', 'posixtime', 'Format', 'dd-MMM-yyyy');
    bin_centre = datetime(round(mean([locs(1:end-1); locs(2:end)])), 'ConvertFrom', 'posixtime', 'Format', 'dd-MMM-yyyy');
    B = table(bin_start', bin_end', bin_centre', 'VariableNames', {'bin_start' 'bin_end' 'bin_centre'});
    writetable(B, replace(JSON_INFILE,'.json','_bin_edges.csv'))

    S.plot_date = datetime(S.record_date);

else
    % Apply rowfun, grouping by speaker to get mean and CI of `diff` scores
    GROUPING_VARS = {'speaker'};
    S = rowfun(@(x) my_mean_ci(x, CI_ALPHA, MIN_ENTRIES), t, ...
        'GroupingVariable', GROUPING_VARS, ...
        'InputVariables', 'diff',...
        'OutputVariableNames', {'mean' 'CI' 'median'});
end

% find any rows with NaN in the mean column, and remove them
ix_drop = isnan(S.mean);
S(ix_drop,:) = [];

% Sort by median
S = sortrows(S, 'median', 'ascend');
n = height(S);

% Output summary table if required
if do_output_summary_table
    if do_group_by_speaker_month
        outfile = replace(JSON_INFILE,'.json','_summary_table_month.csv');
    elseif do_group_by_speaker_year
        outfile = replace(JSON_INFILE,'.json','_summary_table_year.csv');
    elseif do_group_by_speaker_dynamic
        outfile = replace(JSON_INFILE,'.json','_summary_table_dynamic.csv');
    elseif do_group_by_speaker_affiliation
        outfile = replace(JSON_INFILE,'.json','_summary_table_affiliation.csv');
    end
    writetable(S, outfile)
end

% disp(S)
% print the total number of speakers, and rows via summing GroupCount
fprintf(' --> nb: removed %d entries due to having less than %d speeches (e.g. in grouping/period)\n', sum(ix_drop), MIN_ENTRIES)
fprintf('Total number of speakers: %d\n', numel(unique(S.speaker)))
fprintf('Total number of rows: %d\n', sum(S.GroupCount))


%% Plot
% Either just group by speaker; or by year; or with both speaker and year.
figure(1),clf
hold on
if do_group_by_speaker_year | do_group_by_speaker_month | do_group_by_speaker_quarter | do_group_by_speaker_dynamic         % // plot each speaker at a time, for each year

    % -- create plot for each speaker at a time, subsetting the table to a speaker, then plotting their S.mean as scatter, and S.CI as vertical lines, for each year
    u_speakers = unique(S.speaker);
    n = numel(u_speakers);
    if do_color_by_party
        [G,groups] = findgroups(S.affiliation);
        n_clr = numel(groups);
    else
        n_clr = n;
    end

    % -- maximally distinguishable colors
    clrs = distinguishable_colors(n_clr);

    for i = 1:n
        
        % .. subset
        this_speaker = u_speakers{i};
        s = S(strcmp(S.speaker, this_speaker), :);
        if do_color_by_party
            clr = clrs(find(strcmp(groups, s.affiliation{1})),:);
        else
            clr = clrs(i,:);
        end
        
        % .. scatter, and error bars :: add MJITTER to x-values to jitter the scatter points
        s = sortrows(s, 'plot_date', 'ascend');
        xpos = s.plot_date + MJITTER*(2*rand(size(s.year))-1);
        
        % .. add error bars behind
        if show_error_bars
            plot(repmat(xpos',2,1), s.CI', '-', 'Color', clr), hold on
        end
        % .. add line connecting scatter points
        LINE_ALPHA = 0.6;
        plot(xpos, s.mean, '-', 'Color', [clr LINE_ALPHA], 'LineWidth', 2)

        % .. add scatter points
        scatter(xpos, s.mean, MSIZE, clr, 'filled'), hold on

        % .. add final word(name) to last scatter point of this subset of data
        names = split(this_speaker, ' ');
        this_speaker_surname = names{end};
        ix_not_nan = find(~isnan(s.mean), 1, 'last');
        if isempty(ix_not_nan)
            continue
        else
            text(xpos(ix_not_nan(1)), s.median(ix_not_nan(1)), this_speaker_surname,...
                'Color',clr,...
                'FontWeight', 'bold',...
                'FontSize', 12,...
                'HorizontalAlignment', 'left',...
                'VerticalAlignment', 'middle')
        end

        % -- now add a large, open marker for any point, for this speaker, if they were also PM during this point
        % .. read in csv file containing dates of prime minister terms
        PM = readtable(PM_TERMS);
        % .. subset to this speaker's . surname
        PM = PM(strcmp(PM.name, this_speaker_surname), :);
        % .. if we have a non-emtpy table, for each row, get points which are within the term dates
        if ~isempty(PM)
            for j = 1:height(PM)
                ix = s.plot_date >= PM.start_date(j) & s.plot_date <= PM.end_date(j);
                scatter(xpos(ix), s.mean(ix), 200, clr)
            end
        end

    end

    % -- a semi-transparent line for the years where a federal election was held,
    % .. using data from csv `federal_elections.csv`
    E = readtable(ELECTIONS_CSV);
    % .. line y should be min to max of the current Ylim
    yl = get(gca,'YLim')';
    E.polling_day = datetime(E.polling_day);
    plot(repmat(E.polling_day',2,1), repmat(yl,1,numel(E.polling_day)), 'k-', 'Color', [0.5 0.5 0.5 0.15], 'LineWidth', 6)

    % -- dress
    set(gca,'FontSize', 12',...
        'XTick', unique(S.plot_date),...
        'XTickLabelRotation', 45,...
        'Xlim', [min(S.plot_date)-7 max(S.plot_date)+7])
    xlabel('Date')
    % -- set dateformat to dd-MMM-yyyy
    datetick('x', 'dd-mmm-yyyy', 'keeplimits', 'keepticks')

    grid on
    ylabel('Avg. H vs. U diff')
    title('Selected Speakers by mean of H vs. U diff')


elseif do_group_by_speaker_affiliation % // show speakers, grouped by affiliation
    % get affiliations and proceed one by one
    u_affiliations = unique(S.affiliation);
    n = numel(u_affiliations);
    CLRS = distinguishable_colors(n);
    offset = 0;
    names = {};
    for i = 1:n

        % .. setup
        this_affiliation = u_affiliations{i};
        clr = CLRS(i,:);
        s = S(strcmp(S.affiliation, this_affiliation), :);

        % .. add CI as lines
        plot(repmat([1:height(s)] + offset,2,1), s.CI', 'Color', clr, 'LineWidth', 1), hold on
        % .. scatter
        scatter([1:height(s)]' + offset, s.mean, MSIZE, clr, 'filled'), hold on

        % .. collect names for later x-labelling
        names = [names; s.speaker];

        offset = offset + height(s);
    end
    % dress
    ylim = get(gca,'Ylim');
    set(gca,...
        'YTick', ylim(1):1:ylim(2),...
        'Xlim', [0 offset+1],...
        'XTick', 1:offset,...
        'XTicklabels', names,...
        'XTickLabelRotation', 45,...
        'FontSize', 12)
        grid on
    set(gcf,'Position', [1   537   829   440])

elseif ~do_group_by_speaker_year    % // pool all years for each speaker
    % -- place mean as scatter points
    scatter([1:n]', S.median), hold on
    
    % -- now plot vertical lines representing error bars for each scatter point
    % plot(repmat([1:n],2,1), S.CI', 'k-')

    % -- dress
    set(gca,...
        'Xlim', [0 n+1],...
        'XTick', 1:n,...
        'XTicklabels', S.speaker,...
        'XTickLabelRotation', 45,...
        'FontSize', 12)
    grid on
    axis square
    ylabel('Median diff');
    title('Selected Speakers by median diff');

end

% Place the INFILE name in 10 pt font vertically next to the axis
text(1.05,0.5, sprintf(replace(JSON_INFILE,'_','\n')),'FontSize',10,'Units','normalized','HorizontalAlignment','left','VerticalAlignment','middle')


% --------------------------------
function [xbar,ci,median] = my_mean_ci(x, CI_ALPHA, MIN_ENTRIES)

N_SAMPS = 1000;

if numel(x) < MIN_ENTRIES
    xbar = NaN;
    ci = [NaN NaN];
    median = NaN;
    return
else
    xbar = round(mean(bootstrp(N_SAMPS, @mean, x)), 3);
    ci = round(bootci(N_SAMPS, {@mean, x}, 'alpha', CI_ALPHA)',3);
    median = round(mean(bootstrp(N_SAMPS, @median, x)), 3);
end
