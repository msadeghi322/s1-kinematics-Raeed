function shift_err = calculateEncoderPDShiftErr(encoderResults,params)
    % Calculates error in predicting preferred direction shifts for given models
    % Inputs:
    %   encoderResults - The struct output from mwEncoders
    %   params - Paramers struct
    %       .model_aliases - aliases for models names to evaluate
    %       .neural_signal - name of actual neural signal
    % Outputs:
    %   shift_err - table with error values for each crossval sample
    %       Table will match neuron table standard, with columns for:
    %           monkey (meta)
    %           date (meta)
    %           task (meta)
    %           signalID (meta) - only gives back tuned neurons
    %           crossvalID (meta) - [repeatnum foldnum]
    %           {model_aliases}_err
    %
    % Note: this code assumes that the crossTuning table is in a specific order, i.e.
    % neurons are nested inside spacenum, nested inside folds, nested inside repeats
    % and order inside nestings is preserved and identical

    % default params
    model_aliases = encoderResults.params.model_aliases;
    neural_signal = 'S1_FR';

    if nargin>1
        assert(isstruct(params),'params should be a struct!')
        assignParams(who,params);
    end

    % get shift tables
    shift_tables = calculatePDShiftTables(encoderResults,[strcat('glm_',model_aliases,'_model') neural_signal]);
    [~,real_shifts] = getNTidx(shift_tables{end},'signalID',encoderResults.tunedNeurons);

    % figure out what meta columns to keep
    metacols = strcmpi(real_shifts.Properties.VariableDescriptions,'meta');

    % loop through shift tables
    model_err_mat = zeros(height(real_shifts),length(model_aliases));
    for modelnum = 1:length(model_aliases)
        % get modeled shifts
        [~,model_shifts] = getNTidx(shift_tables{modelnum},'signalID',encoderResults.tunedNeurons);
        model_err_mat(:,modelnum) = 1-cos(model_shifts.velPD-real_shifts.velPD);
    end
    model_err = array2table(model_err_mat,'VariableNames',strcat(model_aliases,'_err'));
    model_err.Properties.VariableDescriptions = repmat({'linear'},size(model_aliases));

    shift_err = horzcat(...
        real_shifts(:,metacols),...
        model_err);
