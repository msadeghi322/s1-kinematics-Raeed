%% Set up meta info
    arrayname = 'S1';
    
    if ispc
        dataroot = 'G:\raeed';
    else
        dataroot = '/data/raeed';
    end
    
    datadir = fullfile(dataroot,'project-data','limblab','s1-kinematics','td-library');
    file_info = dir(fullfile(datadir,'*COactpas*.mat'));
    filenames = horzcat({file_info.name})';
    savedir = fullfile(datadir,'lib-s1-kin-paper');

%% Loop through files
trial_data_cell = cell(1,length(filenames));
for filenum = 1:length(filenames)
    %% load and preprocess data
    td = load(fullfile(datadir,[filenames{filenum}]));

    % rename trial_data for ease
    td = td.trial_data;

    % anonymize trial data
    td.monkey = td.monkey(1);

    % first process marker data
    % find times when markers are NaN and replace with zeros temporarily
    for trialnum = 1:length(td)
        markernans = isnan(td(trialnum).markers);
        td(trialnum).markers(markernans) = 0;
        td(trialnum) = smoothSignals(td(trialnum),struct('signals','markers'));
        td(trialnum).markers(markernans) = NaN;
        clear markernans
    end

    % get marker velocity
    td = getDifferential(td,struct('signals','markers','alias','marker_vel'));
    
    % get speed and ds
    td = getNorm(td,struct('signals','vel','field_extra','_norm'));
    td = getDifferential(td,struct('signals','vel_norm','alias','dvel_norm'));
    
    % remove unsorted neurons
    unit_ids = td(1).([arrayname '_unit_guide']);
    unsorted_units = (unit_ids(:,2)==0);
    new_unit_guide = unit_ids(~unsorted_units,:);
    for trialnum = 1:length(td)
        td(trialnum).(sprintf('%s_unit_guide',arrayname)) = new_unit_guide;
        
        spikes = td(trialnum).(sprintf('%s_spikes',arrayname));
        spikes(:,unsorted_units) = [];
        td(trialnum).(sprintf('%s_spikes',arrayname)) = spikes;
    end

    % prep trial data by getting only rewards and trimming to only movements
    % split into trials
    td = splitTD(...
        td,...
        struct(...
            'split_idx_name','idx_startTime',...
            'linked_fields',{{...
                'trialID',...
                'result',...
                'bumpDir',...
                'tgtDir',...
                'ctrHoldBump',...
                'ctrHold',...
                }},...
            'start_name','idx_startTime',...
            'end_name','idx_endTime'));
    [~,td] = getTDidx(td,'result','R');
    td = reorderTDfields(td);
    
    % clean nans out...?
    nanners = isnan(cat(1,td.tgtDir));
    td = td(~nanners);
    fprintf('Removed %d trials because of missing target direction\n',sum(nanners))
    biggers = cat(1,td.ctrHoldBump) & abs(cat(1,td.bumpDir))>360;
    td = td(~biggers);
    fprintf('Removed %d trials because bump direction makes no sense\n',sum(biggers))

    % remove trials where markers aren't present
    bad_trial = false(length(td),1);
    for trialnum = 1:length(td)
        if any(any(isnan(td(trialnum).markers)))
            bad_trial(trialnum) = true;
        end
    end
    td(bad_trial) = [];
    fprintf('Removed %d trials because of missing markers\n',sum(bad_trial))
    
    % remove trials where muscles aren't present
    bad_trial = false(length(td),1);
    for trialnum = 1:length(td)
        if any(any(isnan(td(trialnum).muscle_len) | isnan(td(trialnum).muscle_vel)))
            bad_trial(trialnum) = true;
        end
    end
    td(bad_trial) = [];
    fprintf('Removed %d trials because of missing muscles\n',sum(bad_trial))
    
    % for Chips_20170912, file has bumps on 100% of trials
    if strcmpi(td(1).monkey,'C') && contains(td(1).date_time,'2017/9/12')
        td_copy = td;
        [td_copy.ctrHoldBump] = deal(false);
        td = cat(2,td,td_copy);
        clear td_copy
    end
    
    % split into active and passive
    [~,td_act] = getTDidx(td,'ctrHoldBump',false);
    [~,td_pas] = getTDidx(td,'ctrHoldBump',true);

    % find the relevant movmement onsets
    td_act = getMoveOnsetAndPeak(td_act,struct(...
        'start_idx','idx_goCueTime',...
        'start_idx_offset',20,...
        'peak_idx_offset',20,...
        'end_idx','idx_endTime',...
        'method','peak',...
        'peak_divisor',10,...
        'min_ds',1));
    td_pas = getMoveOnsetAndPeak(td_pas,struct(...
        'start_idx','idx_bumpTime',...
        'start_idx_offset',-5,... % give it some wiggle room
        'peak_idx_offset',-5,... % give it some wiggle room
        'end_idx','idx_goCueTime',...
        'method','peak',...
        'peak_divisor',10,...
        'min_ds',1));
    % throw out all trials where bumpTime and movement_on are more than 3 bins apart
    bad_trial = isnan(cat(1,td_pas.idx_movement_on)) | abs(cat(1,td_pas.idx_movement_on)-cat(1,td_pas.idx_bumpTime))>3;
    td_pas = td_pas(~bad_trial);
    fprintf('Removed %d trials because of bad movement onset\n',sum(bad_trial))

    % even out sizes and put back together
    minsize = min(length(td_act),length(td_pas));
    td_act = td_act(1:minsize);
    td_pas = td_pas(1:minsize);
    td_trim = cat(2,td_act,td_pas);

    % remove low firing neurons
    td_trim = removeBadNeurons(td_trim,struct(...
        'min_fr',1,...
        'fr_window',{{'idx_movement_on',0;'idx_movement_on',11}},...
        'calc_fr',true));

    trial_data_cell{filenum} = td_trim;
end

%% save
save(fullfile(savedir,'actpas_trim_TD.mat'),'trial_data_cell')