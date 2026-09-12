%% ============================================================
% 2026 C题 问题2
%
% 4种负载模型 × 4种光伏模型 = 16种组合
%
% 1. AS-Ridge
% 2. QAR
% 3. Q-Ridge
% 4. AS-SARIMA
%
% ============================================================
% 最终逻辑：
%
% 原预测
% -> 最近30日净负荷残差Q0.8风险校准
% -> 每日0:00制定计划
% -> 当日计划购电不可调整
% -> 逐10min严格因果实际执行
% -> 不足时5倍价格紧急购电
%
% ============================================================
% 本版本与原16组合成功版相比：
%
% 1. cyclePenalty = 0
%
% 2. 计划LP：
%    Wch、Wdis为独立变量
%    允许同时 > 0
%
% 3. 实际因果执行：
%    同样保留Wch、Wdis两个独立变量
%    不再使用Bactual正负强制充/放二选一
%
% 4. 增加：
%    计划同时充放电时段数
%    实际同时充放电时段数
%
% 5. 年末：
%    FORCE_FINAL_SOC_6000 = false
%
%% ============================================================

clear;
clc;
close all;

rng(20260912,'twister');

fprintf('====================================================\n');
fprintf(' C题问题2：16组合热力图\n');
fprintf(' Q0.8 + 因果回放 + 允许同时充放电\n');
fprintf('====================================================\n\n');


%% ============================================================
% 0. 总开关
%% ============================================================

FORCE_FINAL_SOC_6000 = false;

Q_LEVEL = 0.80;

ROLLING_WINDOW_DAYS = 30;

MIN_HISTORY_DAYS = 7;


%% ============================================================
% 1. 模型参数
%% ============================================================

tauL = 0.80;

tauPV = 0.20;

modelNames = [
    "AS-Ridge"
    "QAR"
    "Q-Ridge"
    "AS-SARIMA"
    ];

nModel = length(modelNames);

nCombo = nModel*nModel;


%% ============================================================
% 2. 文件路径
%% ============================================================

baseDir = ...
    'E:\数模\2026年正式比赛\CUMCM2026Problems\C题\附件';


dataFile = ...
    fullfile(baseDir,'附件2.xlsx');


priceFile = ...
    fullfile(baseDir,'附件1.xlsx');


%% 原来已经成功生成的预测缓存

oldPredictionFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_tau08_02_predictions.mat');


predictionFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_16combo_4models_predictions.mat');


%% ★本版本使用新文件名，避免读入旧调度断点

resultMatFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_16combo_NO_CD_MUTEX_FINAL_results.mat');


resultExcelFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_16combo_NO_CD_MUTEX_FINAL_results.xlsx');


dispatchCheckpoint = ...
    fullfile( ...
    baseDir, ...
    'Q2_16combo_NO_CD_MUTEX_dispatch_checkpoint.mat');


predictionCheckpoint = ...
    fullfile( ...
    baseDir, ...
    'Q2_16combo_prediction_checkpoint.mat');


%% ============================================================
% 3. 文件检查
%% ============================================================

if ~isfile(dataFile)

    error('找不到附件2：\n%s',dataFile);

end


if ~isfile(priceFile)

    error('找不到附件1：\n%s',priceFile);

end


%% ============================================================
% 4. 工具箱检查
%% ============================================================

if exist('fitrqlinear','file')~=2

    error('缺少fitrqlinear，需要Statistics and Machine Learning Toolbox。');

end


if exist('arima','file')~=2

    error('缺少arima，需要Econometrics Toolbox。');

end


if exist('linprog','file')~=2

    error('缺少linprog，需要Optimization Toolbox。');

end


%% ============================================================
% 5. 读取全年真实负荷和光伏
%% ============================================================

fprintf('正在读取附件2...\n');


loadRaw = ...
    readmatrix( ...
    dataFile, ...
    'Sheet','小区负载', ...
    'Range','B2:EO366');


pvRaw = ...
    readmatrix( ...
    dataFile, ...
    'Sheet','光伏发电实际功率', ...
    'Range','B2:EO366');


if ~isequal(size(loadRaw),[365,144])

    error('负荷数据不是365×144');

end


if ~isequal(size(pvRaw),[365,144])

    error('光伏数据不是365×144');

end


if any(isnan(loadRaw),'all') || any(isnan(pvRaw),'all')

    error('负荷或光伏数据中存在NaN');

end


%% ============================================================
% 6. 日期
%% ============================================================

datesAll = ...
    ( ...
    datetime(2025,1,1): ...
    days(1): ...
    datetime(2025,12,31) ...
    )';


%% ============================================================
% 7. 正式计算 2/1 ~ 12/31
%% ============================================================

startDay = 32;

endDay = 365;

predDays = startDay:endDay;

nPredDay = length(predDays);

predDates = datesAll(predDays);


%% ============================================================
% 8. 预测模型参数
%% ============================================================

asLambda = 1e-3;

asMaxIter = 50;

asTol = 1e-6;

qarLambda = 0;

qRidgeLambda = 1e-4;

sarimaWindowDays = 90;


%% ============================================================
% 9. 读取已有四模型预测
%% ============================================================

useExistingPrediction = false;


if isfile(predictionFile)

    P = load(predictionFile);

    if isfield(P,'predLoad') ...
            && isfield(P,'predPV') ...
            && isequal(size(P.predLoad),[nPredDay,144,4]) ...
            && isequal(size(P.predPV),[nPredDay,144,4])

        predLoad = P.predLoad;

        predPV = P.predPV;

        useExistingPrediction = true;

        fprintf( ...
            '读取已有四模型预测：\n%s\n\n', ...
            predictionFile);

    end

end


%% 如果主缓存不存在，尝试旧缓存

if ~useExistingPrediction && isfile(oldPredictionFile)

    P = load(oldPredictionFile);

    if isfield(P,'predLoad') ...
            && isfield(P,'predPV') ...
            && isequal(size(P.predLoad),[nPredDay,144,4]) ...
            && isequal(size(P.predPV),[nPredDay,144,4])

        predLoad = P.predLoad;

        predPV = P.predPV;

        useExistingPrediction = true;

        fprintf( ...
            '沿用旧四模型预测结果：\n%s\n\n', ...
            oldPredictionFile);

        save( ...
            predictionFile, ...
            'predLoad', ...
            'predPV', ...
            'modelNames', ...
            'tauL', ...
            'tauPV', ...
            '-v7.3');

    end

end


%% ============================================================
% 10. 若没有预测缓存，再重新训练
%% ============================================================

if ~useExistingPrediction

    fprintf('没有发现已有预测缓存。\n');
    fprintf('开始重新生成4种负载 + 4种光伏预测...\n\n');

    predLoad = nan(nPredDay,144,nModel);

    predPV = nan(nPredDay,144,nModel);

    lastPred = 0;


    %% 恢复预测断点

    if isfile(predictionCheckpoint)

        C = load(predictionCheckpoint);

        if isfield(C,'predLoad') ...
                && isfield(C,'predPV') ...
                && isfield(C,'lastPred') ...
                && isequal(size(C.predLoad),size(predLoad))

            predLoad = C.predLoad;

            predPV = C.predPV;

            lastPred = C.lastPred;

            fprintf( ...
                '恢复预测断点：%d/%d\n', ...
                lastPred,nPredDay);

        end

    end


    ticPrediction = tic;


    for k = (lastPred+1):nPredDay

        d = predDays(k);

        fprintf( ...
            '\n[%03d/%03d] %s\n', ...
            k,nPredDay,string(datesAll(d)));


        trainDays = 15:(d-1);


        %% 丰富特征

        [XL,YL] = ...
            buildLoadRich( ...
            loadRaw,datesAll,trainDays,144);


        [XLtest,~] = ...
            buildLoadRich( ...
            loadRaw,datesAll,d,144);


        [XP,YP] = ...
            buildPVRich( ...
            pvRaw,datesAll,trainDays,144);


        [XPtest,~] = ...
            buildPVRich( ...
            pvRaw,datesAll,d,144);


        %% QAR特征

        [XLqar,YLqar] = ...
            buildLoadQAR( ...
            loadRaw,trainDays,144);


        [XLqarTest,~] = ...
            buildLoadQAR( ...
            loadRaw,d,144);


        [XPqar,YPqar] = ...
            buildPVQAR( ...
            pvRaw,trainDays,144);


        [XPqarTest,~] = ...
            buildPVQAR( ...
            pvRaw,d,144);


        %% ----------------------------------------------------
        % 1 AS-Ridge
        %% ----------------------------------------------------

        fprintf('  1/4 AS-Ridge\n');


        y = ...
            fitASRidge( ...
            XL,YL,XLtest, ...
            tauL, ...
            asLambda, ...
            asMaxIter, ...
            asTol);


        predLoad(k,:,1) = max(y,0)';


        y = ...
            fitASRidge( ...
            XP,YP,XPtest, ...
            tauPV, ...
            asLambda, ...
            asMaxIter, ...
            asTol);


        predPV(k,:,1) = max(y,0)';


        %% ----------------------------------------------------
        % 2 QAR
        %% ----------------------------------------------------

        fprintf('  2/4 QAR\n');


        mdl = ...
            fitrqlinear( ...
            XLqar, ...
            YLqar, ...
            Quantiles=tauL, ...
            Lambda=qarLambda, ...
            Standardize=true, ...
            BetaTolerance=1e-6);


        y = predict(mdl,XLqarTest);

        predLoad(k,:,2) = max(y,0)';


        mdl = ...
            fitrqlinear( ...
            XPqar, ...
            YPqar, ...
            Quantiles=tauPV, ...
            Lambda=qarLambda, ...
            Standardize=true, ...
            BetaTolerance=1e-6);


        y = predict(mdl,XPqarTest);

        predPV(k,:,2) = max(y,0)';


        %% ----------------------------------------------------
        % 3 Q-Ridge
        %% ----------------------------------------------------

        fprintf('  3/4 Q-Ridge\n');


        mdl = ...
            fitrqlinear( ...
            XL, ...
            YL, ...
            Quantiles=tauL, ...
            Lambda=qRidgeLambda, ...
            Standardize=true, ...
            BetaTolerance=1e-6);


        y = predict(mdl,XLtest);

        predLoad(k,:,3) = max(y,0)';


        mdl = ...
            fitrqlinear( ...
            XP, ...
            YP, ...
            Quantiles=tauPV, ...
            Lambda=qRidgeLambda, ...
            Standardize=true, ...
            BetaTolerance=1e-6);


        y = predict(mdl,XPtest);

        predPV(k,:,3) = max(y,0)';


        %% ----------------------------------------------------
        % 4 AS-SARIMA
        %% ----------------------------------------------------

        fprintf('  4/4 AS-SARIMA\n');


        y = ...
            fitSARIMAQuantile( ...
            loadRaw, ...
            d, ...
            144, ...
            tauL, ...
            sarimaWindowDays);


        predLoad(k,:,4) = max(y,0)';


        y = ...
            fitSARIMAQuantile( ...
            pvRaw, ...
            d, ...
            144, ...
            tauPV, ...
            sarimaWindowDays);


        predPV(k,:,4) = max(y,0)';


        %% 断点

        lastPred = k;


        if mod(k,7)==0 || k==nPredDay

            save( ...
                predictionCheckpoint, ...
                'predLoad', ...
                'predPV', ...
                'lastPred', ...
                '-v7.3');

        end

    end


    predictionTime = toc(ticPrediction);


    if any(isnan(predLoad),'all') || any(isnan(predPV),'all')

        error('四模型预测存在NaN');

    end


    save( ...
        predictionFile, ...
        'predLoad', ...
        'predPV', ...
        'modelNames', ...
        'tauL', ...
        'tauPV', ...
        '-v7.3');


else

    predictionTime = 0;

end


%% ============================================================
% 11. 读取电价
%% ============================================================

Tprice = ...
    readtable( ...
    priceFile, ...
    'VariableNamingRule','preserve');


priceRaw = Tprice{:,2};

priceRaw = priceRaw(:);


if length(priceRaw)~=144

    error('附件1电价不是144个时段');

end


%% ============================================================
% 12. 时间轴
%
% 原始：
% 00:10 ... 23:50 00:00(+1)
%
% 内部：
% 00:00 00:10 ... 23:50
%% ============================================================

idx = [144,1:143];


price = [
    priceRaw(end);
    priceRaw(1:end-1)
    ];


actualLoadRaw = loadRaw(predDays,:);

actualPVRaw = pvRaw(predDays,:);


actualLoadRun = actualLoadRaw(:,idx);

actualPVRun = actualPVRaw(:,idx);


predLoadRun = predLoad(:,idx,:);

predPVRun = predPV(:,idx,:);


%% ============================================================
% 13. 储能参数
%% ============================================================

dt = 10/60;

eta_ch = 0.90;

eta_dis = 0.90;

Ecapacity = 12000;

Emin = 1200;

Emax = 10800;

Einitial = 6000;

EfinalTarget = 6000;

Pmax = 5000;

Wmax = Pmax*dt;

emergencyFactor = 5;


%% ★取消充放电惩罚

cyclePenalty = 0;


%% 保留弃光微小择优项

curtailPenalty = 1e-5;


fprintf('\n');
fprintf('储能参数：\n');

fprintf('Emin = %.0f kWh\n',Emin);

fprintf('Emax = %.0f kWh\n',Emax);

fprintf('Wmax = %.6f kWh/10min\n',Wmax);

fprintf('cyclePenalty = %.1e\n',cyclePenalty);

fprintf('允许同时充放电：是\n');

fprintf('强制年末6000：%s\n\n', ...
    yesno(FORCE_FINAL_SOC_6000));


%% ============================================================
% 14. LP设置
%% ============================================================

lpOptions = ...
    optimoptions( ...
    'linprog', ...
    'Algorithm','dual-simplex-highs', ...
    'Display','none');


%% ============================================================
% 15. 16组索引
%% ============================================================

comboLoadIdx = zeros(nCombo,1);

comboPVIdx = zeros(nCombo,1);

comboName = strings(nCombo,1);


c = 1;


for i = 1:nModel

    for j = 1:nModel

        comboLoadIdx(c) = i;

        comboPVIdx(c) = j;

        comboName(c) = ...
            "L-" ...
            +modelNames(i) ...
            +" + PV-" ...
            +modelNames(j);

        c = c+1;

    end

end


LoadModel = modelNames(comboLoadIdx);

PVModel = modelNames(comboPVIdx);


%% ============================================================
% 16. 净负荷原始预测指标
%% ============================================================

actualNetRun = ...
    actualLoadRun ...
    -actualPVRun;


RawNet_MAE = zeros(nCombo,1);

RawNet_RMSE = zeros(nCombo,1);

RawNet_WAPE = zeros(nCombo,1);

RawNet_Bias = zeros(nCombo,1);


for combo = 1:nCombo

    iLoad = comboLoadIdx(combo);

    iPV = comboPVIdx(combo);


    rawNet = ...
        predLoadRun(:,:,iLoad) ...
        -predPVRun(:,:,iPV);


    e = ...
        rawNet ...
        -actualNetRun;


    RawNet_MAE(combo) = ...
        mean(abs(e),'all');


    RawNet_RMSE(combo) = ...
        sqrt(mean(e.^2,'all'));


    RawNet_WAPE(combo) = ...
        100 ...
        *sum(abs(e),'all') ...
        /max(sum(abs(actualNetRun),'all'),eps);


    RawNet_Bias(combo) = ...
        mean(e,'all');

end


%% ============================================================
% 17. 初始化16组合全过程
%% ============================================================

planGridAll = ...
    zeros(nPredDay,144,nCombo);


%% ★新增：计划充电和计划放电

planChargeAll = ...
    zeros(nPredDay,144,nCombo);


planDischargeAll = ...
    zeros(nPredDay,144,nCombo);


emergencyAll = ...
    zeros(nPredDay,144,nCombo);


chargeAll = ...
    zeros(nPredDay,144,nCombo);


dischargeAll = ...
    zeros(nPredDay,144,nCombo);


actualSpillAll = ...
    zeros(nPredDay,144,nCombo);


planCurtailAll = ...
    zeros(nPredDay,144,nCombo);


socStartAll = ...
    zeros(nPredDay,nCombo);


socEndAll = ...
    zeros(nPredDay,nCombo);


planCostDayAll = ...
    zeros(nPredDay,nCombo);


emergencyCostDayAll = ...
    zeros(nPredDay,nCombo);


q80MeanCombo = zeros(nCombo,1);

q80MinCombo = zeros(nCombo,1);

q80MaxCombo = zeros(nCombo,1);


CorrectedNet_MAE = zeros(nCombo,1);

CorrectedNet_Bias = zeros(nCombo,1);


%% ============================================================
% 18. 调度断点
%% ============================================================

lastCombo = 0;


if isfile(dispatchCheckpoint)

    D = load(dispatchCheckpoint);


    requiredCheckpointFields = {
        'lastCombo'
        'planGridAll'
        'planChargeAll'
        'planDischargeAll'
        };


    checkpointOK = true;


    for kk = 1:length(requiredCheckpointFields)

        if ~isfield(D,requiredCheckpointFields{kk})

            checkpointOK = false;

        end

    end


    if checkpointOK ...
            && isequal(size(D.planGridAll),size(planGridAll))

        lastCombo = D.lastCombo;

        planGridAll = D.planGridAll;

        planChargeAll = D.planChargeAll;

        planDischargeAll = D.planDischargeAll;

        emergencyAll = D.emergencyAll;

        chargeAll = D.chargeAll;

        dischargeAll = D.dischargeAll;

        actualSpillAll = D.actualSpillAll;

        planCurtailAll = D.planCurtailAll;

        socStartAll = D.socStartAll;

        socEndAll = D.socEndAll;

        planCostDayAll = D.planCostDayAll;

        emergencyCostDayAll = D.emergencyCostDayAll;

        q80MeanCombo = D.q80MeanCombo;

        q80MinCombo = D.q80MinCombo;

        q80MaxCombo = D.q80MaxCombo;

        CorrectedNet_MAE = D.CorrectedNet_MAE;

        CorrectedNet_Bias = D.CorrectedNet_Bias;


        fprintf( ...
            '恢复NO-CD-MUTEX调度断点：组合%d/16\n', ...
            lastCombo);

    end

end


%% ============================================================
% 19. 逐组合执行
%% ============================================================

ticDispatch = tic;


for combo = (lastCombo+1):nCombo

    iLoad = comboLoadIdx(combo);

    iPV = comboPVIdx(combo);


    fprintf('\n');
    fprintf('####################################################\n');
    fprintf(' 组合 %02d / 16\n',combo);
    fprintf(' 负载模型：%s\n',modelNames(iLoad));
    fprintf(' 光伏模型：%s\n',modelNames(iPV));
    fprintf('####################################################\n');


    %% ========================================================
    % 19.1 原始净负荷预测
    %% ========================================================

    loadForecastRaw = ...
        predLoadRun(:,:,iLoad);


    pvForecast = ...
        predPVRun(:,:,iPV);


    forecastNet = ...
        loadForecastRaw ...
        -pvForecast;


    %% ========================================================
    % 19.2 历史净负荷残差
    %
    % residual = actual - forecast
    %% ========================================================

    residualNet = ...
        actualNetRun ...
        -forecastNet;


    %% ========================================================
    % 19.3 严格因果Q0.8
    %% ========================================================

    q80Correction = ...
        zeros(nPredDay,144);


    calibrationActive = ...
        false(nPredDay,1);


    for d = 1:nPredDay

        histEnd = d-1;

        histStart = ...
            max( ...
            1, ...
            d-ROLLING_WINDOW_DAYS);


        if histEnd<histStart

            continue;

        end


        nHist = ...
            histEnd-histStart+1;


        if nHist<MIN_HISTORY_DAYS

            continue;

        end


        calibrationActive(d) = true;


        for t = 1:144

            r = ...
                residualNet( ...
                histStart:histEnd, ...
                t);


            r = ...
                r(isfinite(r));


            if length(r)>=MIN_HISTORY_DAYS

                q80Correction(d,t) = ...
                    quantile(r,Q_LEVEL);

            end

        end

    end


    %% ========================================================
    % 19.4 修正净负荷
    %% ========================================================

    correctedNet = ...
        forecastNet ...
        +q80Correction;


    correctedLoad = ...
        correctedNet ...
        +pvForecast;


    correctedLoad = ...
        max(correctedLoad,0);


    %% ========================================================
    % Q80统计
    %% ========================================================

    activeMask = ...
        repmat( ...
        calibrationActive, ...
        1,144);


    qUse = ...
        q80Correction(activeMask);


    if isempty(qUse)

        q80MeanCombo(combo) = 0;

        q80MinCombo(combo) = 0;

        q80MaxCombo(combo) = 0;

    else

        q80MeanCombo(combo) = mean(qUse);

        q80MinCombo(combo) = min(qUse);

        q80MaxCombo(combo) = max(qUse);

    end


    %% ========================================================
    % 校准后净负荷指标
    %% ========================================================

    eCorr = ...
        correctedNet ...
        -actualNetRun;


    CorrectedNet_MAE(combo) = ...
        mean(abs(eCorr),'all');


    CorrectedNet_Bias(combo) = ...
        mean(eCorr,'all');


    %% ========================================================
    % 19.5 全年逐日运行
    %% ========================================================

    Ecurrent = Einitial;


    for d = 1:nPredDay

        if mod(d-1,30)==0 || d==nPredDay

            fprintf( ...
                '  Day %03d / %03d\n', ...
                d,nPredDay);

        end


        EdayStart = Ecurrent;

        socStartAll(d,combo) = EdayStart;


        isLastDay = ...
            (d==nPredDay);


        %% 年末SOC

        if isLastDay && FORCE_FINAL_SOC_6000

            terminalLow = EfinalTarget;

            terminalHigh = EfinalTarget;

        else

            terminalLow = Emin;

            terminalHigh = Emax;

        end


        loadForecast = ...
            correctedLoad(d,:)';


        pvForecastDay = ...
            pvForecast(d,:)';


        %% ====================================================
        % 0:00计划LP
        %
        % ★允许同时充放电
        %% ====================================================

        plan = ...
            solveDailyPlanTerminalSOC( ...
            loadForecast, ...
            pvForecastDay, ...
            price, ...
            EdayStart, ...
            terminalLow, ...
            terminalHigh, ...
            dt, ...
            eta_ch, ...
            eta_dis, ...
            Emin, ...
            Emax, ...
            Wmax, ...
            cyclePenalty, ...
            curtailPenalty, ...
            lpOptions);


        planGridAll(d,:,combo) = ...
            plan.Wgrid';


        %% ★保存计划充放电

        planChargeAll(d,:,combo) = ...
            plan.Wch';


        planDischargeAll(d,:,combo) = ...
            plan.Wdis';


        planCurtailAll(d,:,combo) = ...
            plan.Wcut';


        planCostDayAll(d,combo) = ...
            sum( ...
            price ...
            .*plan.Wgrid);


        %% ====================================================
        % 严格因果实际回放
        %
        % ★允许同时充放电
        %% ====================================================

        replay = ...
            replayActualDayCausalAllowSimultaneous( ...
            actualLoadRun(d,:)', ...
            actualPVRun(d,:)', ...
            plan.Wgrid, ...
            plan.Wch, ...
            plan.Wdis, ...
            EdayStart, ...
            dt, ...
            eta_ch, ...
            eta_dis, ...
            Emin, ...
            Emax, ...
            Wmax, ...
            isLastDay ...
                && FORCE_FINAL_SOC_6000, ...
            EfinalTarget);


        chargeAll(d,:,combo) = ...
            replay.Wch';


        dischargeAll(d,:,combo) = ...
            replay.Wdis';


        actualSpillAll(d,:,combo) = ...
            replay.Wspill';


        emergencyAll(d,:,combo) = ...
            replay.Wem';


        emergencyCostDayAll(d,combo) = ...
            sum( ...
            emergencyFactor ...
            .*price ...
            .*replay.Wem);


        Ecurrent = ...
            replay.Eend;


        socEndAll(d,combo) = ...
            Ecurrent;

    end


    %% ========================================================
    % 当前组合完成
    %% ========================================================

    comboPlanCost = ...
        sum(planCostDayAll(:,combo));


    comboEmergencyCost = ...
        sum(emergencyCostDayAll(:,combo));


    comboTotalCost = ...
        comboPlanCost ...
        +comboEmergencyCost;


    planSimNow = ...
        nnz( ...
        planChargeAll(:,:,combo)>1e-8 ...
        & ...
        planDischargeAll(:,:,combo)>1e-8);


    actualSimNow = ...
        nnz( ...
        chargeAll(:,:,combo)>1e-8 ...
        & ...
        dischargeAll(:,:,combo)>1e-8);


    fprintf('\n');
    fprintf('组合完成：\n');

    fprintf('Q80均值：%.2f kW\n', ...
        q80MeanCombo(combo));

    fprintf('计划购电量：%.2f kWh\n', ...
        sum(planGridAll(:,:,combo),'all'));

    fprintf('紧急购电量：%.2f kWh\n', ...
        sum(emergencyAll(:,:,combo),'all'));

    fprintf('actualSpill：%.2f kWh\n', ...
        sum(actualSpillAll(:,:,combo),'all'));

    fprintf('计划同时充放电：%d 个时段\n', ...
        planSimNow);

    fprintf('实际同时充放电：%d 个时段\n', ...
        actualSimNow);

    fprintf('总成本：%.2f 元\n', ...
        comboTotalCost);


    %% ========================================================
    % 断点保存
    %% ========================================================

    lastCombo = combo;


    save( ...
        dispatchCheckpoint, ...
        'lastCombo', ...
        'planGridAll', ...
        'planChargeAll', ...
        'planDischargeAll', ...
        'emergencyAll', ...
        'chargeAll', ...
        'dischargeAll', ...
        'actualSpillAll', ...
        'planCurtailAll', ...
        'socStartAll', ...
        'socEndAll', ...
        'planCostDayAll', ...
        'emergencyCostDayAll', ...
        'q80MeanCombo', ...
        'q80MinCombo', ...
        'q80MaxCombo', ...
        'CorrectedNet_MAE', ...
        'CorrectedNet_Bias', ...
        '-v7.3');

end


dispatchTime = toc(ticDispatch);


%% ============================================================
% 20. 汇总
%% ============================================================

PlanEnergy_kWh = zeros(nCombo,1);

EmergencyEnergy_kWh = zeros(nCombo,1);

PlanCost_yuan = zeros(nCombo,1);

EmergencyCost_yuan = zeros(nCombo,1);

TotalCost_yuan = zeros(nCombo,1);

PlanCurtail_kWh = zeros(nCombo,1);

ActualSpill_kWh = zeros(nCombo,1);

ChargeEnergy_kWh = zeros(nCombo,1);

DischargeEnergy_kWh = zeros(nCombo,1);

EmergencyDays = zeros(nCombo,1);

EmergencySlots = zeros(nCombo,1);

MeanSOCend_kWh = zeros(nCombo,1);

MinSOCend_kWh = zeros(nCombo,1);

MaxSOCend_kWh = zeros(nCombo,1);

FinalSOC_kWh = zeros(nCombo,1);


%% ★新增

PlanSimultaneousSlots = ...
    zeros(nCombo,1);


ActualSimultaneousSlots = ...
    zeros(nCombo,1);


for combo = 1:nCombo

    pg = planGridAll(:,:,combo);

    em = emergencyAll(:,:,combo);


    PlanEnergy_kWh(combo) = ...
        sum(pg,'all');


    EmergencyEnergy_kWh(combo) = ...
        sum(em,'all');


    PlanCost_yuan(combo) = ...
        sum(planCostDayAll(:,combo));


    EmergencyCost_yuan(combo) = ...
        sum(emergencyCostDayAll(:,combo));


    TotalCost_yuan(combo) = ...
        PlanCost_yuan(combo) ...
        +EmergencyCost_yuan(combo);


    PlanCurtail_kWh(combo) = ...
        sum(planCurtailAll(:,:,combo),'all');


    ActualSpill_kWh(combo) = ...
        sum(actualSpillAll(:,:,combo),'all');


    ChargeEnergy_kWh(combo) = ...
        sum(chargeAll(:,:,combo),'all');


    DischargeEnergy_kWh(combo) = ...
        sum(dischargeAll(:,:,combo),'all');


    EmergencyDays(combo) = ...
        sum(any(em>1e-7,2));


    EmergencySlots(combo) = ...
        nnz(em>1e-7);


    MeanSOCend_kWh(combo) = ...
        mean(socEndAll(:,combo));


    MinSOCend_kWh(combo) = ...
        min(socEndAll(:,combo));


    MaxSOCend_kWh(combo) = ...
        max(socEndAll(:,combo));


    FinalSOC_kWh(combo) = ...
        socEndAll(end,combo);


    %% ★同时充放电统计

    PlanSimultaneousSlots(combo) = ...
        nnz( ...
        planChargeAll(:,:,combo)>1e-8 ...
        & ...
        planDischargeAll(:,:,combo)>1e-8);


    ActualSimultaneousSlots(combo) = ...
        nnz( ...
        chargeAll(:,:,combo)>1e-8 ...
        & ...
        dischargeAll(:,:,combo)>1e-8);

end


%% ============================================================
% 21. 最终汇总表
%% ============================================================

summaryTable = ...
    table( ...
    (1:nCombo)', ...
    comboName, ...
    LoadModel, ...
    PVModel, ...
    RawNet_MAE, ...
    RawNet_RMSE, ...
    RawNet_WAPE, ...
    RawNet_Bias, ...
    q80MeanCombo, ...
    q80MinCombo, ...
    q80MaxCombo, ...
    CorrectedNet_MAE, ...
    CorrectedNet_Bias, ...
    PlanEnergy_kWh, ...
    PlanCost_yuan, ...
    EmergencyEnergy_kWh, ...
    EmergencyCost_yuan, ...
    TotalCost_yuan, ...
    PlanCurtail_kWh, ...
    ActualSpill_kWh, ...
    EmergencyDays, ...
    EmergencySlots, ...
    ChargeEnergy_kWh, ...
    DischargeEnergy_kWh, ...
    MeanSOCend_kWh, ...
    MinSOCend_kWh, ...
    MaxSOCend_kWh, ...
    FinalSOC_kWh, ...
    PlanSimultaneousSlots, ...
    ActualSimultaneousSlots, ...
    'VariableNames',{ ...
    'ComboID', ...
    'Combination', ...
    'LoadModel', ...
    'PVModel', ...
    'RawNet_MAE_kW', ...
    'RawNet_RMSE_kW', ...
    'RawNet_WAPE_pct', ...
    'RawNet_Bias_kW', ...
    'Q80_Mean_kW', ...
    'Q80_Min_kW', ...
    'Q80_Max_kW', ...
    'CorrectedNet_MAE_kW', ...
    'CorrectedNet_Bias_kW', ...
    'PlanEnergy_kWh', ...
    'PlanCost_yuan', ...
    'EmergencyEnergy_kWh', ...
    'EmergencyCost_yuan', ...
    'TotalCost_yuan', ...
    'PlanCurtail_kWh', ...
    'ActualSpill_kWh', ...
    'EmergencyDays', ...
    'EmergencySlots', ...
    'ChargeEnergy_kWh', ...
    'DischargeEnergy_kWh', ...
    'MeanSOCend_kWh', ...
    'MinSOCend_kWh', ...
    'MaxSOCend_kWh', ...
    'FinalSOC_kWh', ...
    'PlanSimultaneousSlots', ...
    'ActualSimultaneousSlots'} ...
    );


summaryByCost = ...
    sortrows( ...
    summaryTable, ...
    'TotalCost_yuan', ...
    'ascend');


fprintf('\n');
fprintf('====================================================\n');
fprintf(' 16种组合最终总成本排名\n');
fprintf('====================================================\n');


disp( ...
    summaryByCost(:,{ ...
    'ComboID', ...
    'LoadModel', ...
    'PVModel', ...
    'PlanCost_yuan', ...
    'EmergencyCost_yuan', ...
    'TotalCost_yuan', ...
    'PlanSimultaneousSlots', ...
    'ActualSimultaneousSlots'}));


%% ============================================================
% 22. 最优组合
%% ============================================================

[bestCost,bestCombo] = ...
    min(TotalCost_yuan);


fprintf('\n');
fprintf('====================================================\n');
fprintf(' 最优组合\n');
fprintf('====================================================\n');

fprintf('ComboID：%d\n',bestCombo);

fprintf('负载预测模型：%s\n', ...
    LoadModel(bestCombo));

fprintf('光伏预测模型：%s\n', ...
    PVModel(bestCombo));

fprintf('原始净负荷MAE：%.2f kW\n', ...
    RawNet_MAE(bestCombo));

fprintf('Q0.8风险校准后MAE：%.2f kW\n', ...
    CorrectedNet_MAE(bestCombo));

fprintf('Q0.8平均修正：%.2f kW\n', ...
    q80MeanCombo(bestCombo));

fprintf('计划购电量：%.2f kWh\n', ...
    PlanEnergy_kWh(bestCombo));

fprintf('计划购电费：%.2f 元\n', ...
    PlanCost_yuan(bestCombo));

fprintf('紧急购电量：%.2f kWh\n', ...
    EmergencyEnergy_kWh(bestCombo));

fprintf('紧急购电费：%.2f 元\n', ...
    EmergencyCost_yuan(bestCombo));

fprintf('actualSpill：%.2f kWh\n', ...
    ActualSpill_kWh(bestCombo));

fprintf('计划同时充放电时段：%d\n', ...
    PlanSimultaneousSlots(bestCombo));

fprintf('实际同时充放电时段：%d\n', ...
    ActualSimultaneousSlots(bestCombo));

fprintf('全年总成本：%.2f 元\n', ...
    bestCost);

fprintf('最终SOC：%.2f kWh\n', ...
    FinalSOC_kWh(bestCombo));

fprintf('====================================================\n');


%% ============================================================
% 23. 转成4×4矩阵
%% ============================================================

costMatrix = zeros(4,4);

emergencyMatrix = zeros(4,4);

spillMatrix = zeros(4,4);

planMatrix = zeros(4,4);

q80Matrix = zeros(4,4);


%% ★新增

planSimMatrix = zeros(4,4);

actualSimMatrix = zeros(4,4);


for combo = 1:nCombo

    i = comboLoadIdx(combo);

    j = comboPVIdx(combo);


    costMatrix(i,j) = ...
        TotalCost_yuan(combo);


    emergencyMatrix(i,j) = ...
        EmergencyEnergy_kWh(combo);


    spillMatrix(i,j) = ...
        ActualSpill_kWh(combo);


    planMatrix(i,j) = ...
        PlanEnergy_kWh(combo);


    q80Matrix(i,j) = ...
        q80MeanCombo(combo);


    planSimMatrix(i,j) = ...
        PlanSimultaneousSlots(combo);


    actualSimMatrix(i,j) = ...
        ActualSimultaneousSlots(combo);

end


%% ============================================================
% ★校验QAR + AS-Ridge
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' 关键一致性校验\n');
fprintf('====================================================\n');

fprintf('QAR负载 + AS-Ridge光伏：\n');

fprintf('costMatrix(2,1) = %.2f 元\n', ...
    costMatrix(2,1));

fprintf('单组合参考值约 = 13933244.47 元\n');

fprintf('差值 = %+.2f 元\n', ...
    costMatrix(2,1)-13933244.47);

fprintf('====================================================\n');


%% ============================================================
% 24. 总成本热力图
%% ============================================================

figure('Color','w');


imagesc(costMatrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel('光伏预测模型');

ylabel('负载预测模型');


title('16种组合全年总购电成本 / 元');


for i = 1:4

    for j = 1:4

        text( ...
            j,i, ...
            sprintf('%.0f',costMatrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'VerticalAlignment','middle', ...
            'FontWeight','bold', ...
            'Color','k');

    end

end


%% ============================================================
% 25. 紧急购电热力图
%% ============================================================

figure('Color','w');


imagesc(emergencyMatrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel('光伏预测模型');

ylabel('负载预测模型');


title('16种组合全年紧急购电量 / kWh');


for i = 1:4

    for j = 1:4

        text( ...
            j,i, ...
            sprintf('%.0f',emergencyMatrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'FontWeight','bold');

    end

end


%% ============================================================
% 26. actualSpill热力图
%% ============================================================

figure('Color','w');


imagesc(spillMatrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel('光伏预测模型');

ylabel('负载预测模型');


title('16种组合全年actualSpill / kWh');


for i = 1:4

    for j = 1:4

        text( ...
            j,i, ...
            sprintf('%.0f',spillMatrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'FontWeight','bold');

    end

end


%% ============================================================
% 27. Q80热力图
%% ============================================================

figure('Color','w');


imagesc(q80Matrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel('光伏预测模型');

ylabel('负载预测模型');


title('16种组合净负荷Q0.8平均风险修正 / kW');


for i = 1:4

    for j = 1:4

        text( ...
            j,i, ...
            sprintf('%.1f',q80Matrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'FontWeight','bold');

    end

end


%% ============================================================
% 28. ★计划同时充放电热力图
%% ============================================================

figure('Color','w');


imagesc(planSimMatrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel('光伏预测模型');

ylabel('负载预测模型');


title('计划阶段同时充放电时段数');


for i = 1:4

    for j = 1:4

        text( ...
            j,i, ...
            sprintf('%d',planSimMatrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'FontWeight','bold');

    end

end


%% ============================================================
% 29. ★实际同时充放电热力图
%% ============================================================

figure('Color','w');


imagesc(actualSimMatrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel('光伏预测模型');

ylabel('负载预测模型');


title('实际阶段同时充放电时段数');


for i = 1:4

    for j = 1:4

        text( ...
            j,i, ...
            sprintf('%d',actualSimMatrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'FontWeight','bold');

    end

end


%% ============================================================
% 30. 写Excel
%% ============================================================

if isfile(resultExcelFile)

    delete(resultExcelFile);

end


writetable( ...
    summaryTable, ...
    resultExcelFile, ...
    'Sheet','16组合最终结果');


writetable( ...
    summaryByCost, ...
    resultExcelFile, ...
    'Sheet','总成本排名');


writeMatrixSheet( ...
    resultExcelFile, ...
    '总成本矩阵', ...
    modelNames, ...
    costMatrix);


writeMatrixSheet( ...
    resultExcelFile, ...
    '紧急购电矩阵', ...
    modelNames, ...
    emergencyMatrix);


writeMatrixSheet( ...
    resultExcelFile, ...
    'actualSpill矩阵', ...
    modelNames, ...
    spillMatrix);


writeMatrixSheet( ...
    resultExcelFile, ...
    'Q80平均修正矩阵', ...
    modelNames, ...
    q80Matrix);


writeMatrixSheet( ...
    resultExcelFile, ...
    '计划同时充放电', ...
    modelNames, ...
    planSimMatrix);


writeMatrixSheet( ...
    resultExcelFile, ...
    '实际同时充放电', ...
    modelNames, ...
    actualSimMatrix);


%% ============================================================
% 31. 保存MAT
%% ============================================================

save( ...
    resultMatFile, ...
    'modelNames', ...
    'predLoad', ...
    'predPV', ...
    'summaryTable', ...
    'summaryByCost', ...
    'costMatrix', ...
    'emergencyMatrix', ...
    'spillMatrix', ...
    'q80Matrix', ...
    'planSimMatrix', ...
    'actualSimMatrix', ...
    'planGridAll', ...
    'planChargeAll', ...
    'planDischargeAll', ...
    'emergencyAll', ...
    'actualSpillAll', ...
    'chargeAll', ...
    'dischargeAll', ...
    'socStartAll', ...
    'socEndAll', ...
    'bestCombo', ...
    'bestCost', ...
    'FORCE_FINAL_SOC_6000', ...
    'Q_LEVEL', ...
    'ROLLING_WINDOW_DAYS', ...
    'MIN_HISTORY_DAYS', ...
    'cyclePenalty', ...
    '-v7.3');


%% ============================================================
% 32. 成功后删除断点
%% ============================================================

if isfile(dispatchCheckpoint)

    delete(dispatchCheckpoint);

end


if isfile(predictionCheckpoint)

    delete(predictionCheckpoint);

end


fprintf('\n');
fprintf('====================================================\n');
fprintf(' 16组合全部完成\n');
fprintf('====================================================\n');

fprintf('预测耗时：%.2f min\n', ...
    predictionTime/60);

fprintf('调度耗时：%.2f min\n', ...
    dispatchTime/60);

fprintf('\n结果Excel：\n%s\n', ...
    resultExcelFile);

fprintf('\n结果MAT：\n%s\n', ...
    resultMatFile);

fprintf('====================================================\n');


%% ============================================================
% 函数1：负载丰富特征
%% ============================================================

function [X,Y] = buildLoadRich( ...
    data,dates,dayList,nTime)


dayList = dayList(:)';


X = zeros(length(dayList)*nTime,7);

Y = zeros(length(dayList)*nTime,1);


slot = (0:nTime-1)';


sinDay = sin(2*pi*slot/nTime);

cosDay = cos(2*pi*slot/nTime);


r = 1;


for d = dayList

    wd = weekday(dates(d));


    sinWeek = ...
        sin(2*pi*(wd-1)/7);


    cosWeek = ...
        cos(2*pi*(wd-1)/7);


    rows = r:(r+nTime-1);


    X(rows,1) = data(d-1,:)';

    X(rows,2) = data(d-7,:)';

    X(rows,3) = data(d-14,:)';

    X(rows,4) = sinDay;

    X(rows,5) = cosDay;

    X(rows,6) = sinWeek;

    X(rows,7) = cosWeek;


    Y(rows) = data(d,:)';


    r = r+nTime;

end

end


%% ============================================================
% 函数2：光伏丰富特征
%% ============================================================

function [X,Y] = buildPVRich( ...
    data,dates,dayList,nTime)


dayList = dayList(:)';


X = zeros(length(dayList)*nTime,9);

Y = zeros(length(dayList)*nTime,1);


slot = (0:nTime-1)';


sinDay = sin(2*pi*slot/nTime);

cosDay = cos(2*pi*slot/nTime);


r = 1;


for d = dayList

    doy = ...
        day(dates(d),'dayofyear');


    sinYear = ...
        sin(2*pi*(doy-1)/365);


    cosYear = ...
        cos(2*pi*(doy-1)/365);


    rows = r:(r+nTime-1);


    X(rows,1) = data(d-1,:)';

    X(rows,2) = data(d-2,:)';

    X(rows,3) = data(d-3,:)';

    X(rows,4) = data(d-7,:)';

    X(rows,5) = data(d-14,:)';

    X(rows,6) = sinDay;

    X(rows,7) = cosDay;

    X(rows,8) = sinYear;

    X(rows,9) = cosYear;


    Y(rows) = data(d,:)';


    r = r+nTime;

end

end


%% ============================================================
% 函数3：负载QAR
%% ============================================================

function [X,Y] = buildLoadQAR( ...
    data,dayList,nTime)


dayList = dayList(:)';


X = zeros(length(dayList)*nTime,3);

Y = zeros(length(dayList)*nTime,1);


r = 1;


for d = dayList

    rows = r:(r+nTime-1);


    X(rows,1) = data(d-1,:)';

    X(rows,2) = data(d-7,:)';

    X(rows,3) = data(d-14,:)';


    Y(rows) = data(d,:)';


    r = r+nTime;

end

end


%% ============================================================
% 函数4：光伏QAR
%% ============================================================

function [X,Y] = buildPVQAR( ...
    data,dayList,nTime)


dayList = dayList(:)';


X = zeros(length(dayList)*nTime,5);

Y = zeros(length(dayList)*nTime,1);


r = 1;


for d = dayList

    rows = r:(r+nTime-1);


    X(rows,1) = data(d-1,:)';

    X(rows,2) = data(d-2,:)';

    X(rows,3) = data(d-3,:)';

    X(rows,4) = data(d-7,:)';

    X(rows,5) = data(d-14,:)';


    Y(rows) = data(d,:)';


    r = r+nTime;

end

end


%% ============================================================
% 函数5：AS-Ridge
%% ============================================================

function yPred = fitASRidge( ...
    Xtrain,Ytrain,Xtest, ...
    tau,lambda,maxIter,tol)


muX = mean(Xtrain,1);

sdX = std(Xtrain,0,1);

sdX(sdX<1e-10) = 1;


Xtr = ...
    (Xtrain-muX)./sdX;


Xte = ...
    (Xtest-muX)./sdX;


muY = mean(Ytrain);

sdY = std(Ytrain);


if sdY<1e-10

    sdY = 1;

end


y = ...
    (Ytrain-muY)/sdY;


X1 = [
    ones(size(Xtr,1),1), ...
    Xtr
    ];


Xt = [
    ones(size(Xte,1),1), ...
    Xte
    ];


p = size(X1,2);


R = eye(p);

R(1,1) = 0;


beta = ...
    (X1'*X1+lambda*R) ...
    \ ...
    (X1'*y);


for iter = 1:maxIter

    e = ...
        y-X1*beta;


    w = ...
        (1-tau) ...
        *ones(size(e));


    w(e>=0) = tau;


    Xw = ...
        X1.*sqrt(w);


    yw = ...
        y.*sqrt(w);


    betaNew = ...
        (Xw'*Xw+lambda*R) ...
        \ ...
        (Xw'*yw);


    change = ...
        norm(betaNew-beta) ...
        / ...
        max(norm(beta),1e-8);


    beta = betaNew;


    if change<tol

        break;

    end

end


yPred = ...
    (Xt*beta)*sdY+muY;

end


%% ============================================================
% 函数6：AS-SARIMA
%% ============================================================

function yPred = fitSARIMAQuantile( ...
    data,d,nTime,tau,windowDays)


firstDay = ...
    max(1,d-windowDays);


history = ...
    data(firstDay:(d-1),:);


nHistDays = ...
    size(history,1);


y = ...
    reshape(history.',[],1);


try

    Mdl = ...
        arima( ...
        'Constant',NaN, ...
        'ARLags',1, ...
        'SARLags',nTime);


    EstMdl = ...
        estimate( ...
        Mdl, ...
        y, ...
        'Display','off');


    residual = ...
        infer(EstMdl,y);


    centerForecast = ...
        forecast( ...
        EstMdl, ...
        nTime, ...
        'Y0',y);


    qShift = zeros(nTime,1);


    if length(residual)==nHistDays*nTime

        residualMat = ...
            reshape( ...
            residual, ...
            nTime, ...
            nHistDays)';


        globalR = ...
            residual(isfinite(residual));


        if isempty(globalR)

            globalQ = 0;

        else

            globalQ = ...
                quantile(globalR,tau);

        end


        for t = 1:nTime

            r = residualMat(:,t);

            r = r(isfinite(r));


            if length(r)>=5

                qShift(t) = ...
                    quantile(r,tau);

            else

                qShift(t) = globalQ;

            end

        end


    else

        r = residual(isfinite(residual));


        if isempty(r)

            qShift(:) = 0;

        else

            qShift(:) = ...
                quantile(r,tau);

        end

    end


    yPred = ...
        centerForecast ...
        +qShift;


catch

    base = ...
        data(d-1,:)';


    firstErr = ...
        max(2,firstDay+1);


    qShift = zeros(nTime,1);


    if firstErr<=d-1

        delta = ...
            data(firstErr:(d-1),:) ...
            - ...
            data((firstErr-1):(d-2),:);


        for t = 1:nTime

            r = delta(:,t);

            r = r(isfinite(r));


            if ~isempty(r)

                qShift(t) = ...
                    quantile(r,tau);

            end

        end

    end


    yPred = ...
        base+qShift;

end


yPred = max(yPred,0);

end


%% ============================================================
% 函数7：计划LP
%
% ★无互斥约束
%% ============================================================

function plan = solveDailyPlanTerminalSOC( ...
    Pload, ...
    Pv, ...
    price, ...
    Estart, ...
    terminalLow, ...
    terminalHigh, ...
    dt, ...
    eta_ch, ...
    eta_dis, ...
    Emin, ...
    Emax, ...
    Wmax, ...
    cyclePenalty, ...
    curtailPenalty, ...
    options)


N = length(price);


Wload = Pload(:)*dt;

Wpv = Pv(:)*dt;

price = price(:);


idxGrid = 1:N;

idxCh = N+(1:N);

idxDis = 2*N+(1:N);

idxCut = 3*N+(1:N);

idxE = 4*N+(1:N+1);


nvar = 5*N+1;


%% 目标

f = zeros(nvar,1);


f(idxGrid) = price;


%% ★现在为0

f(idxCh) = cyclePenalty;

f(idxDis) = cyclePenalty;


f(idxCut) = curtailPenalty;


%% 等式

Aeq = zeros(2*N+1,nvar);

beq = zeros(2*N+1,1);


%% 供需平衡

for t = 1:N

    Aeq(t,idxGrid(t)) = 1;

    Aeq(t,idxCh(t)) = -1;

    Aeq(t,idxDis(t)) = 1;

    Aeq(t,idxCut(t)) = -1;


    beq(t) = ...
        Wload(t)-Wpv(t);

end


%% SOC动态

for t = 1:N

    r = N+t;


    Aeq(r,idxE(t)) = -1;

    Aeq(r,idxE(t+1)) = 1;

    Aeq(r,idxCh(t)) = -eta_ch;

    Aeq(r,idxDis(t)) = 1/eta_dis;

end


%% 初始SOC

Aeq(2*N+1,idxE(1)) = 1;

beq(2*N+1) = Estart;


%% 上下界

lb = zeros(nvar,1);

ub = inf(nvar,1);


ub(idxCh) = Wmax;

ub(idxDis) = Wmax;


%% 没有Wch/Wdis互斥


ub(idxCut) = Wpv;


lb(idxE) = Emin;

ub(idxE) = Emax;


lb(idxE(end)) = terminalLow;

ub(idxE(end)) = terminalHigh;


[x,~,exitflag] = ...
    linprog( ...
    f, ...
    [],[], ...
    Aeq,beq, ...
    lb,ub, ...
    options);


if exitflag<=0

    error( ...
        ['计划LP失败：', ...
        'Estart=%.2f，terminal=[%.2f,%.2f]'], ...
        Estart, ...
        terminalLow, ...
        terminalHigh);

end


plan.Wgrid = x(idxGrid);

plan.Wch = x(idxCh);

plan.Wdis = x(idxDis);

plan.Wcut = x(idxCut);

plan.E = x(idxE);

end


%% ============================================================
% 函数8：严格因果实际执行
%
% ★允许同时充放电
%% ============================================================

function replay = replayActualDayCausalAllowSimultaneous( ...
    Pload, ...
    Pv, ...
    Wgrid, ...
    WchPlan, ...
    WdisPlan, ...
    Estart, ...
    dt, ...
    eta_ch, ...
    eta_dis, ...
    Emin, ...
    Emax, ...
    Wmax, ...
    forceFinalSOC, ...
    EfinalTarget)


N = length(Wgrid);


Wload = Pload(:)*dt;

Wpv = Pv(:)*dt;

Wgrid = Wgrid(:);

WchPlan = WchPlan(:);

WdisPlan = WdisPlan(:);


Wch = zeros(N,1);

Wdis = zeros(N,1);

Wspill = zeros(N,1);

Wem = zeros(N,1);


E = zeros(N+1,1);

E(1) = Estart;


for t = 1:N

    Ecurrent = E(t);


    %% ========================================================
    % 下一时刻允许SOC
    %% ========================================================

    EnextLow = Emin;

    EnextHigh = Emax;


    if forceFinalSOC

        remainingSlots = N-t;


        EnextMinReach = ...
            EfinalTarget ...
            -remainingSlots ...
            *eta_ch ...
            *Wmax;


        EnextMaxReach = ...
            EfinalTarget ...
            +remainingSlots ...
            *Wmax/eta_dis;


        EnextLow = ...
            max(Emin,EnextMinReach);


        EnextHigh = ...
            min(Emax,EnextMaxReach);


        if EnextLow>EnextHigh+1e-7

            error('终点SOC可达区间不可行');

        end

    end


    %% ========================================================
    % 先执行日前计划
    %
    % ★Wch/Wdis独立
    %% ========================================================

    WchNow = ...
        min( ...
        max(WchPlan(t),0), ...
        Wmax);


    WdisNow = ...
        min( ...
        max(WdisPlan(t),0), ...
        Wmax);


    Enew = ...
        Ecurrent ...
        +eta_ch*WchNow ...
        -WdisNow/eta_dis;


    %% ========================================================
    % SOC过低
    %
    % 先减少放电
    % 再增加充电
    %% ========================================================

    if Enew<EnextLow

        needIncreaseSOC = ...
            EnextLow-Enew;


        reduceDischarge = ...
            min( ...
            WdisNow, ...
            needIncreaseSOC*eta_dis);


        WdisNow = ...
            WdisNow-reduceDischarge;


        Enew = ...
            Ecurrent ...
            +eta_ch*WchNow ...
            -WdisNow/eta_dis;


        if Enew<EnextLow-1e-10

            addCharge = ...
                min( ...
                Wmax-WchNow, ...
                (EnextLow-Enew)/eta_ch);


            WchNow = ...
                WchNow+addCharge;


            Enew = ...
                Ecurrent ...
                +eta_ch*WchNow ...
                -WdisNow/eta_dis;

        end

    end


    %% ========================================================
    % SOC过高
    %
    % 先减少充电
    % 再增加放电
    %% ========================================================

    if Enew>EnextHigh

        needDecreaseSOC = ...
            Enew-EnextHigh;


        reduceCharge = ...
            min( ...
            WchNow, ...
            needDecreaseSOC/eta_ch);


        WchNow = ...
            WchNow-reduceCharge;


        Enew = ...
            Ecurrent ...
            +eta_ch*WchNow ...
            -WdisNow/eta_dis;


        if Enew>EnextHigh+1e-10

            addDischarge = ...
                min( ...
                Wmax-WdisNow, ...
                (Enew-EnextHigh)*eta_dis);


            WdisNow = ...
                WdisNow+addDischarge;


            Enew = ...
                Ecurrent ...
                +eta_ch*WchNow ...
                -WdisNow/eta_dis;

        end

    end


    if Enew<EnextLow-1e-6 ...
            || ...
            Enew>EnextHigh+1e-6

        error( ...
            ['初始计划动作无法调整到SOC可行区间：', ...
            't=%d,Enew=%.6f'], ...
            t,Enew);

    end


    %% ========================================================
    % 当前真实供需差
    %
    % >0 缺电
    % <0 富余
    %% ========================================================

    residual = ...
        Wload(t) ...
        +WchNow ...
        -Wpv(t) ...
        -Wgrid(t) ...
        -WdisNow;


    %% ========================================================
    % 缺电
    %% ========================================================

    if residual>0

        %% 第一步：减少充电

        maxReduceChargeSOC = ...
            max( ...
            (Enew-EnextLow)/eta_ch, ...
            0);


        reduceCharge = ...
            min([ ...
            residual, ...
            WchNow, ...
            maxReduceChargeSOC]);


        WchNow = ...
            WchNow-reduceCharge;


        residual = ...
            residual-reduceCharge;


        Enew = ...
            Enew ...
            -eta_ch*reduceCharge;


        %% 第二步：增加放电

        if residual>1e-12

            maxExtraDischargeSOC = ...
                eta_dis ...
                *max( ...
                Enew-EnextLow, ...
                0);


            maxExtraDischarge = ...
                min( ...
                Wmax-WdisNow, ...
                maxExtraDischargeSOC);


            extraDischarge = ...
                min( ...
                residual, ...
                maxExtraDischarge);


            WdisNow = ...
                WdisNow+extraDischarge;


            residual = ...
                residual-extraDischarge;


            Enew = ...
                Enew ...
                -extraDischarge/eta_dis;

        end


        %% 第三步：紧急购电

        Wem(t) = ...
            max(residual,0);


        Wspill(t) = 0;


    %% ========================================================
    % 富余
    %% ========================================================

    elseif residual<0

        surplus = -residual;


        %% 第一步：减少放电

        maxReduceDischargeSOC = ...
            eta_dis ...
            *max( ...
            EnextHigh-Enew, ...
            0);


        reduceDischarge = ...
            min([ ...
            surplus, ...
            WdisNow, ...
            maxReduceDischargeSOC]);


        WdisNow = ...
            WdisNow-reduceDischarge;


        surplus = ...
            surplus-reduceDischarge;


        Enew = ...
            Enew ...
            +reduceDischarge/eta_dis;


        %% 第二步：增加充电

        if surplus>1e-12

            maxExtraChargeSOC = ...
                max( ...
                EnextHigh-Enew, ...
                0) ...
                /eta_ch;


            maxExtraCharge = ...
                min( ...
                Wmax-WchNow, ...
                maxExtraChargeSOC);


            extraCharge = ...
                min( ...
                surplus, ...
                maxExtraCharge);


            WchNow = ...
                WchNow+extraCharge;


            surplus = ...
                surplus-extraCharge;


            Enew = ...
                Enew ...
                +eta_ch*extraCharge;

        end


        %% 第三步：未利用富余

        Wspill(t) = ...
            max(surplus,0);


        Wem(t) = 0;


    else

        Wem(t) = 0;

        Wspill(t) = 0;

    end


    %% ========================================================
    % 保存
    %
    % ★这里允许二者同时 > 0
    %% ========================================================

    Wch(t) = WchNow;

    Wdis(t) = WdisNow;


    E(t+1) = ...
        Ecurrent ...
        +eta_ch*Wch(t) ...
        -Wdis(t)/eta_dis;


    %% 数值修正

    if abs(E(t+1)-Emin)<1e-9

        E(t+1) = Emin;

    end


    if abs(E(t+1)-Emax)<1e-9

        E(t+1) = Emax;

    end


    %% SOC检查

    if E(t+1)<Emin-1e-6 ...
            || ...
            E(t+1)>Emax+1e-6

        error( ...
            ['SOC越界：', ...
            't=%d,Ebefore=%.6f,Eafter=%.6f'], ...
            t,Ecurrent,E(t+1));

    end


    if E(t+1)<EnextLow-1e-6 ...
            || ...
            E(t+1)>EnextHigh+1e-6

        error( ...
            ['SOC违反终点可达约束：', ...
            't=%d,Eafter=%.6f'], ...
            t,E(t+1));

    end


    %% 功率检查

    if Wch(t)<-1e-8 ...
            || ...
            Wch(t)>Wmax+1e-6

        error('充电功率越界：t=%d',t);

    end


    if Wdis(t)<-1e-8 ...
            || ...
            Wdis(t)>Wmax+1e-6

        error('放电功率越界：t=%d',t);

    end


    %% ========================================================
    % 供需平衡检查
    %% ========================================================

    balanceError = ...
        Wgrid(t) ...
        +Wpv(t) ...
        +Wdis(t) ...
        +Wem(t) ...
        -Wload(t) ...
        -Wch(t) ...
        -Wspill(t);


    if abs(balanceError)>1e-5

        error( ...
            ['实际供需平衡失败：', ...
            't=%d,error=%.8f'], ...
            t,balanceError);

    end

end


if forceFinalSOC

    if abs(E(end)-EfinalTarget)>1e-4

        error( ...
            '最终SOC没有达到6000：%.6f', ...
            E(end));

    end

end


replay.Wch = Wch;

replay.Wdis = Wdis;

replay.Wspill = Wspill;

replay.Wem = Wem;

replay.E = E;

replay.Eend = E(end);

end


%% ============================================================
% 函数9：Excel矩阵
%% ============================================================

function writeMatrixSheet( ...
    excelFile, ...
    sheetName, ...
    modelNames, ...
    M)


out = cell(5,5);


out{1,1} = ...
    '负载\光伏';


for j = 1:4

    out{1,j+1} = ...
        char(modelNames(j));

end


for i = 1:4

    out{i+1,1} = ...
        char(modelNames(i));


    for j = 1:4

        out{i+1,j+1} = ...
            M(i,j);

    end

end


writecell( ...
    out, ...
    excelFile, ...
    'Sheet',sheetName, ...
    'Range','A1');

end


%% ============================================================
% 函数10：是/否
%% ============================================================

function s = yesno(tf)

if tf

    s = '是';

else

    s = '否';

end

end