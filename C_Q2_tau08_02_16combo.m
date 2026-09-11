%% ============================================================
% 2026 C题 问题2
%
% tau_L  = 0.80
% tau_PV = 0.20
%
% 四种模型：
% 1. AS-Ridge
% 2. QAR
% 3. Q-Ridge
% 4. AS-SARIMA
%
% 完整流程：
% 滚动预测
% -> 预测误差
% -> 16种负载/光伏组合
% -> 购电与储能调度
% -> 紧急购电
% -> 全年总成本
%
%% ============================================================

clear;
clc;
close all;

rng(20260911,'twister');

fprintf('====================================================\n');
fprintf(' C题问题2：tauL=0.8，tauPV=0.2\n');
fprintf(' 4模型 × 4模型 = 16种组合\n');
fprintf('====================================================\n\n');


%% ============================================================
% 1. 非对称风险参数
%% ============================================================

tauL  = 0.80;
tauPV = 0.20;

fprintf('负载 tau_L  = %.2f\n',tauL);
fprintf('光伏 tau_PV = %.2f\n\n',tauPV);


%% ============================================================
% 2. 模型名称
%% ============================================================

modelNames = [
    "AS-Ridge"
    "QAR"
    "Q-Ridge"
    "AS-SARIMA"
];

nModel = 4;


%% ============================================================
% 3. 文件
%% ============================================================

scriptDir = fileparts(mfilename('fullpath'));

if isempty(scriptDir)
    scriptDir = pwd;
end

dataFile  = fullfile(scriptDir,'附件2.xlsx');
priceFile = fullfile(scriptDir,'附件1.xlsx');

if ~isfile(dataFile)
    error('找不到附件2.xlsx');
end

if ~isfile(priceFile)
    error('找不到附件1.xlsx');
end


%% ============================================================
% 4. 读取负载和光伏
%% ============================================================

load_data = readmatrix( ...
    dataFile, ...
    'Sheet','小区负载', ...
    'Range','B2:EO366');

pv_data = readmatrix( ...
    dataFile, ...
    'Sheet','光伏发电实际功率', ...
    'Range','B2:EO366');

[nDay,nTime] = size(load_data);

if nDay~=365 || nTime~=144
    error('数据尺寸不是365×144');
end

if any(isnan(load_data),'all') || any(isnan(pv_data),'all')
    error('数据中存在NaN');
end

fprintf('数据读取完成：365 × 144\n\n');


%% ============================================================
% 5. 日期
%% ============================================================

dates = ...
    (datetime(2025,1,1):days(1):datetime(2025,12,31))';


%% ============================================================
% 6. 预测日期：2月1日~12月31日
%% ============================================================

startDay = 32;
endDay   = 365;

predDays = startDay:endDay;
nPredDay = length(predDays);

actualLoad = load_data(predDays,:);
actualPV   = pv_data(predDays,:);

actualNet = actualLoad-actualPV;

fprintf('正式预测天数：%d\n\n',nPredDay);


%% ============================================================
% 7. 检查函数
%% ============================================================

if exist('fitrqlinear','file')~=2
    error('缺少 fitrqlinear，需要 Statistics and Machine Learning Toolbox');
end

if exist('arima','file')~=2
    error('缺少 arima，需要 Econometrics Toolbox');
end

if exist('linprog','file')~=2
    error('缺少 linprog，需要 Optimization Toolbox');
end


%% ============================================================
% 8. 参数
%% ============================================================

% AS-Ridge
asLambda  = 1e-3;
asMaxIter = 50;
asTol     = 1e-6;

% QAR：不加岭惩罚
qarLambda = 0;

% Q-Ridge
qRidgeLambda = 1e-4;

% SARIMA只用最近90天
sarimaWindowDays = 90;


%% ============================================================
% 9. 预测矩阵
%
% day × time × model
%% ============================================================

predLoad = nan(nPredDay,nTime,nModel);
predPV   = nan(nPredDay,nTime,nModel);


%% ============================================================
% 10. 预测断点
%% ============================================================

predCheckpoint = fullfile( ...
    scriptDir, ...
    'Q2_tau08_02_prediction_checkpoint.mat');

lastPred = 0;

if isfile(predCheckpoint)

    S = load(predCheckpoint);

    if isfield(S,'predLoad') && ...
       isfield(S,'predPV') && ...
       isfield(S,'lastPred') && ...
       isequal(size(S.predLoad),size(predLoad))

        predLoad = S.predLoad;
        predPV   = S.predPV;
        lastPred = S.lastPred;

        fprintf('恢复预测断点：%d/%d\n\n', ...
            lastPred,nPredDay);
    end
end


%% ============================================================
% 11. 全年滚动预测
%% ============================================================

ticPrediction = tic;

for k = (lastPred+1):nPredDay

    d = predDays(k);

    fprintf('\n[%03d/%03d] %s\n', ...
        k,nPredDay,string(dates(d)));

    % 最大滞后14天
    trainDays = 15:(d-1);


    %% --------------------------------------------------------
    % 丰富特征：AS-Ridge / Q-Ridge
    %% --------------------------------------------------------

    [XL,YL] = buildLoadRich( ...
        load_data,dates,trainDays,nTime);

    [XLtest,~] = buildLoadRich( ...
        load_data,dates,d,nTime);

    [XP,YP] = buildPVRich( ...
        pv_data,dates,trainDays,nTime);

    [XPtest,~] = buildPVRich( ...
        pv_data,dates,d,nTime);


    %% --------------------------------------------------------
    % QAR纯时序特征
    %% --------------------------------------------------------

    [XLqar,YLqar] = buildLoadQAR( ...
        load_data,trainDays,nTime);

    [XLqarTest,~] = buildLoadQAR( ...
        load_data,d,nTime);

    [XPqar,YPqar] = buildPVQAR( ...
        pv_data,trainDays,nTime);

    [XPqarTest,~] = buildPVQAR( ...
        pv_data,d,nTime);


    %% ========================================================
    % 1. AS-Ridge
    %% ========================================================

    fprintf('  1/4 AS-Ridge\n');

    y = fitASRidge( ...
        XL,YL,XLtest, ...
        tauL,asLambda,asMaxIter,asTol);

    predLoad(k,:,1) = max(y,0)';

    y = fitASRidge( ...
        XP,YP,XPtest, ...
        tauPV,asLambda,asMaxIter,asTol);

    predPV(k,:,1) = max(y,0)';


    %% ========================================================
    % 2. QAR
    %% ========================================================

    fprintf('  2/4 QAR\n');

    mdl = fitrqlinear( ...
        XLqar,YLqar, ...
        Quantiles=tauL, ...
        Lambda=qarLambda, ...
        Standardize=true, ...
        BetaTolerance=1e-6);

    y = predict(mdl,XLqarTest);

    predLoad(k,:,2) = max(y,0)';

    mdl = fitrqlinear( ...
        XPqar,YPqar, ...
        Quantiles=tauPV, ...
        Lambda=qarLambda, ...
        Standardize=true, ...
        BetaTolerance=1e-6);

    y = predict(mdl,XPqarTest);

    predPV(k,:,2) = max(y,0)';


    %% ========================================================
    % 3. Q-Ridge
    %% ========================================================

    fprintf('  3/4 Q-Ridge\n');

    mdl = fitrqlinear( ...
        XL,YL, ...
        Quantiles=tauL, ...
        Lambda=qRidgeLambda, ...
        Standardize=true, ...
        BetaTolerance=1e-6);

    y = predict(mdl,XLtest);

    predLoad(k,:,3) = max(y,0)';

    mdl = fitrqlinear( ...
        XP,YP, ...
        Quantiles=tauPV, ...
        Lambda=qRidgeLambda, ...
        Standardize=true, ...
        BetaTolerance=1e-6);

    y = predict(mdl,XPtest);

    predPV(k,:,3) = max(y,0)';


    %% ========================================================
    % 4. AS-SARIMA
    %% ========================================================

    fprintf('  4/4 AS-SARIMA\n');

    y = fitSARIMAQuantile( ...
        load_data,d,nTime, ...
        tauL,sarimaWindowDays);

    predLoad(k,:,4) = max(y,0)';

    y = fitSARIMAQuantile( ...
        pv_data,d,nTime, ...
        tauPV,sarimaWindowDays);

    predPV(k,:,4) = max(y,0)';


    %% --------------------------------------------------------
    % 保存断点
    %% --------------------------------------------------------

    lastPred = k;

    if mod(k,7)==0 || k==nPredDay

        save( ...
            predCheckpoint, ...
            'predLoad','predPV','lastPred', ...
            'tauL','tauPV', ...
            '-v7.3');

        fprintf('  已保存预测断点\n');
    end

end

predictionTime = toc(ticPrediction);

fprintf('\n预测完成：%.2f min\n', ...
    predictionTime/60);


%% ============================================================
% 12. 检查
%% ============================================================

if any(isnan(predLoad),'all') || any(isnan(predPV),'all')
    error('预测结果存在NaN');
end


%% ============================================================
% 13. 四种负载模型误差
%% ============================================================

loadMetrics = table;

for m = 1:nModel

    T = evaluateForecast( ...
        actualLoad, ...
        predLoad(:,:,m), ...
        tauL, ...
        "Load", ...
        modelNames(m));

    loadMetrics = [loadMetrics;T]; %#ok<AGROW>
end

fprintf('\n================ 负载模型 ================\n');
disp(loadMetrics);


%% ============================================================
% 14. 四种光伏模型误差
%% ============================================================

pvMetrics = table;

for m = 1:nModel

    T = evaluateForecast( ...
        actualPV, ...
        predPV(:,:,m), ...
        tauPV, ...
        "PV", ...
        modelNames(m));

    pvMetrics = [pvMetrics;T]; %#ok<AGROW>
end

fprintf('\n================ 光伏模型 ================\n');
disp(pvMetrics);


%% ============================================================
% 15. 16种组合净负荷误差
%% ============================================================

nCombo = 16;

comboLoadIdx = zeros(nCombo,1);
comboPVIdx   = zeros(nCombo,1);

comboName = strings(nCombo,1);

Net_MAE          = zeros(nCombo,1);
Net_RMSE         = zeros(nCombo,1);
Net_WAPE         = zeros(nCombo,1);
Net_Bias         = zeros(nCombo,1);
Net_R2           = zeros(nCombo,1);
Net_UnderRate    = zeros(nCombo,1);
Net_UnderEnergy  = zeros(nCombo,1);

c = 1;

for i = 1:nModel

    for j = 1:nModel

        comboLoadIdx(c) = i;
        comboPVIdx(c)   = j;

        comboName(c) = ...
            "L-" + modelNames(i) + ...
            " + PV-" + modelNames(j);

        predNet = ...
            predLoad(:,:,i)-predPV(:,:,j);

        a = actualNet(:);
        p = predNet(:);

        e = p-a;

        Net_MAE(c) = ...
            mean(abs(e));

        Net_RMSE(c) = ...
            sqrt(mean(e.^2));

        Net_WAPE(c) = ...
            100*sum(abs(e)) / ...
            max(sum(abs(a)),eps);

        Net_Bias(c) = ...
            mean(e);

        SSE = sum((a-p).^2);
        SST = sum((a-mean(a)).^2);

        Net_R2(c) = ...
            1-SSE/max(SST,eps);

        Net_UnderRate(c) = ...
            100*mean(p<a);

        Net_UnderEnergy(c) = ...
            sum(max(a-p,0))*(10/60);

        c = c+1;
    end
end


LoadModel = modelNames(comboLoadIdx);
PVModel   = modelNames(comboPVIdx);

netMetrics = table( ...
    (1:nCombo)', ...
    comboName, ...
    LoadModel, ...
    PVModel, ...
    Net_MAE, ...
    Net_RMSE, ...
    Net_WAPE, ...
    Net_Bias, ...
    Net_R2, ...
    Net_UnderRate, ...
    Net_UnderEnergy, ...
    'VariableNames',{ ...
    'ComboID', ...
    'Combination', ...
    'LoadModel', ...
    'PVModel', ...
    'MAE_kW', ...
    'RMSE_kW', ...
    'WAPE_pct', ...
    'Bias_kW', ...
    'R2', ...
    'UnderRate_pct', ...
    'UnderEnergy_kWh'});

fprintf('\n============= 16组合净负荷指标 =============\n');
disp(netMetrics);


%% ============================================================
% 16. 保存预测
%% ============================================================

save( ...
    fullfile(scriptDir,'Q2_tau08_02_predictions.mat'), ...
    'predLoad','predPV', ...
    'actualLoad','actualPV','actualNet', ...
    'modelNames','loadMetrics','pvMetrics', ...
    'netMetrics','tauL','tauPV', ...
    '-v7.3');


%% ============================================================
% 17. 读取附件1电价
%% ============================================================

Tprice = readtable( ...
    priceFile, ...
    'VariableNamingRule','preserve');

priceRaw = Tprice{:,2};
priceRaw = priceRaw(:);

if length(priceRaw)~=144
    error('附件1电价不是144个时段');
end


%% ============================================================
% 18. 时间轴旋转到0:00开始
%
% 原顺序：
% 00:10 ... 23:50 ... 次日00:00
%
% 内部：
% 00:00 ... 23:50
%% ============================================================

idx = [144,1:143];

price = [ ...
    priceRaw(end); ...
    priceRaw(1:end-1)];

actualLoadRun = actualLoad(:,idx);
actualPVRun   = actualPV(:,idx);

predLoadRun = predLoad(:,idx,:);
predPVRun   = predPV(:,idx,:);


%% ============================================================
% 19. 储能参数
%% ============================================================

dt = 10/60;

eta  = 0.90;

Emin = 1200;
Emax = 10800;

Pmax = 5000;

Wmax = Pmax*dt;

% 与上一版比较保持一致
Einitial = 6000;

% 紧急购电 = 5倍
emergencyFactor = 5;


%% ============================================================
% 20. LP
%% ============================================================

lpOptions = optimoptions( ...
    'linprog', ...
    'Algorithm','dual-simplex-highs', ...
    'Display','none');


%% ============================================================
% 21. 保存16种方案全过程
%% ============================================================

planGridAll = ...
    zeros(nPredDay,nTime,nCombo);

emergencyAll = ...
    zeros(nPredDay,nTime,nCombo);

chargeAll = ...
    zeros(nPredDay,nTime,nCombo);

dischargeAll = ...
    zeros(nPredDay,nTime,nCombo);

curtailAll = ...
    zeros(nPredDay,nTime,nCombo);

socStartAll = ...
    zeros(nPredDay,nCombo);

socEndAll = ...
    zeros(nPredDay,nCombo);

planCostDayAll = ...
    zeros(nPredDay,nCombo);

emergencyCostDayAll = ...
    zeros(nPredDay,nCombo);


%% ============================================================
% 22. 调度断点
%% ============================================================

dispatchCheckpoint = fullfile( ...
    scriptDir, ...
    'Q2_tau08_02_dispatch_checkpoint.mat');

lastCombo = 0;

if isfile(dispatchCheckpoint)

    D = load(dispatchCheckpoint);

    if isfield(D,'lastCombo') && ...
       isfield(D,'planGridAll') && ...
       isequal(size(D.planGridAll),size(planGridAll))

        lastCombo = D.lastCombo;

        planGridAll = D.planGridAll;
        emergencyAll = D.emergencyAll;

        chargeAll = D.chargeAll;
        dischargeAll = D.dischargeAll;
        curtailAll = D.curtailAll;

        socStartAll = D.socStartAll;
        socEndAll = D.socEndAll;

        planCostDayAll = D.planCostDayAll;
        emergencyCostDayAll = D.emergencyCostDayAll;

        fprintf('\n恢复调度到组合 %d/16\n',lastCombo);
    end
end


%% ============================================================
% 23. 16种组合全年调度
%% ============================================================

ticDispatch = tic;

for combo = (lastCombo+1):nCombo

    iLoad = comboLoadIdx(combo);
    iPV   = comboPVIdx(combo);

    fprintf('\n');
    fprintf('####################################################\n');
    fprintf('组合 %02d/16\n',combo);
    fprintf('负载：%s\n',modelNames(iLoad));
    fprintf('光伏：%s\n',modelNames(iPV));
    fprintf('####################################################\n');

    Ecurrent = Einitial;

    for d = 1:nPredDay

        if mod(d-1,30)==0 || d==nPredDay
            fprintf('  Day %03d/%03d\n',d,nPredDay);
        end

        loadForecast = ...
            predLoadRun(d,:,iLoad)';

        pvForecast = ...
            predPVRun(d,:,iPV)';

        loadActual = ...
            actualLoadRun(d,:)';

        pvActual = ...
            actualPVRun(d,:)';


        %% 当前SOC

        socStartAll(d,combo) = Ecurrent;


        %% ----------------------------------------------------
        % 0:00制定当日购电计划
        %% ----------------------------------------------------

        plan = solveDailyPlanLP( ...
            loadForecast, ...
            pvForecast, ...
            price, ...
            Ecurrent, ...
            dt,eta, ...
            Emin,Emax,Wmax, ...
            lpOptions);


        planGridAll(d,:,combo) = ...
            plan.Wgrid';


        planCostDayAll(d,combo) = ...
            sum(price.*plan.Wgrid);


        %% ----------------------------------------------------
        % 用真实数据进行当天回放
        %% ----------------------------------------------------

        replay = replayActualDay( ...
            loadActual, ...
            pvActual, ...
            plan.Wgrid, ...
            Ecurrent, ...
            dt,eta, ...
            Emin,Emax,Wmax);


        emergencyAll(d,:,combo) = ...
            replay.Wem';

        chargeAll(d,:,combo) = ...
            replay.Wch';

        dischargeAll(d,:,combo) = ...
            replay.Wdis';

        curtailAll(d,:,combo) = ...
            replay.Wcut';


        emergencyCostDayAll(d,combo) = ...
            sum( ...
            emergencyFactor ...
            .* price ...
            .* replay.Wem);


        Ecurrent = replay.Eend;

        socEndAll(d,combo) = Ecurrent;

    end


    fprintf('组合完成。\n');

    fprintf('计划购电量：%.2f kWh\n', ...
        sum(planGridAll(:,:,combo),'all'));

    fprintf('紧急购电量：%.2f kWh\n', ...
        sum(emergencyAll(:,:,combo),'all'));

    fprintf('计划费用：%.2f 元\n', ...
        sum(planCostDayAll(:,combo)));

    fprintf('紧急费用：%.2f 元\n', ...
        sum(emergencyCostDayAll(:,combo)));

    fprintf('总成本：%.2f 元\n', ...
        sum(planCostDayAll(:,combo)) + ...
        sum(emergencyCostDayAll(:,combo)));


    %% 保存

    lastCombo = combo;

    save( ...
        dispatchCheckpoint, ...
        'lastCombo', ...
        'planGridAll','emergencyAll', ...
        'chargeAll','dischargeAll','curtailAll', ...
        'socStartAll','socEndAll', ...
        'planCostDayAll','emergencyCostDayAll', ...
        '-v7.3');

end

dispatchTime = toc(ticDispatch);


%% ============================================================
% 24. 16种方案最终指标
%% ============================================================

PlanEnergy_kWh       = zeros(nCombo,1);
EmergencyEnergy_kWh  = zeros(nCombo,1);

PlanCost_yuan        = zeros(nCombo,1);
EmergencyCost_yuan   = zeros(nCombo,1);
TotalCost_yuan       = zeros(nCombo,1);

EmergencyDays        = zeros(nCombo,1);
EmergencySlots       = zeros(nCombo,1);

MaxEmergency_kWh     = zeros(nCombo,1);

ChargeEnergy_kWh     = zeros(nCombo,1);
DischargeEnergy_kWh  = zeros(nCombo,1);
CurtailEnergy_kWh    = zeros(nCombo,1);

FinalSOC_kWh         = zeros(nCombo,1);


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
        PlanCost_yuan(combo) + ...
        EmergencyCost_yuan(combo);

    EmergencyDays(combo) = ...
        sum(any(em>1e-6,2));

    EmergencySlots(combo) = ...
        nnz(em>1e-6);

    MaxEmergency_kWh(combo) = ...
        max(em,[],'all');

    ChargeEnergy_kWh(combo) = ...
        sum(chargeAll(:,:,combo),'all');

    DischargeEnergy_kWh(combo) = ...
        sum(dischargeAll(:,:,combo),'all');

    CurtailEnergy_kWh(combo) = ...
        sum(curtailAll(:,:,combo),'all');

    FinalSOC_kWh(combo) = ...
        socEndAll(end,combo);

end


%% ============================================================
% 25. 完整总表
%% ============================================================

summaryTable = table( ...
    (1:nCombo)', ...
    comboName, ...
    LoadModel, ...
    PVModel, ...
    Net_MAE, ...
    Net_RMSE, ...
    Net_WAPE, ...
    Net_Bias, ...
    Net_R2, ...
    Net_UnderRate, ...
    Net_UnderEnergy, ...
    PlanEnergy_kWh, ...
    EmergencyEnergy_kWh, ...
    PlanCost_yuan, ...
    EmergencyCost_yuan, ...
    TotalCost_yuan, ...
    EmergencyDays, ...
    EmergencySlots, ...
    MaxEmergency_kWh, ...
    ChargeEnergy_kWh, ...
    DischargeEnergy_kWh, ...
    CurtailEnergy_kWh, ...
    FinalSOC_kWh, ...
    'VariableNames',{ ...
    'ComboID', ...
    'Combination', ...
    'LoadModel', ...
    'PVModel', ...
    'Net_MAE_kW', ...
    'Net_RMSE_kW', ...
    'Net_WAPE_pct', ...
    'Net_Bias_kW', ...
    'Net_R2', ...
    'Net_UnderRate_pct', ...
    'Net_UnderEnergy_kWh', ...
    'PlanEnergy_kWh', ...
    'EmergencyEnergy_kWh', ...
    'PlanCost_yuan', ...
    'EmergencyCost_yuan', ...
    'TotalCost_yuan', ...
    'EmergencyDays', ...
    'EmergencySlots', ...
    'MaxEmergency_kWh', ...
    'ChargeEnergy_kWh', ...
    'DischargeEnergy_kWh', ...
    'CurtailEnergy_kWh', ...
    'FinalSOC_kWh'});


%% ============================================================
% 26. 总成本排名
%% ============================================================

summaryByCost = ...
    sortrows( ...
    summaryTable, ...
    'TotalCost_yuan', ...
    'ascend');


fprintf('\n');
fprintf('====================================================\n');
fprintf('                16种方案总成本排名\n');
fprintf('====================================================\n');

disp(summaryByCost);


%% ============================================================
% 27. 最低成本
%% ============================================================

[bestCost,bestCombo] = ...
    min(TotalCost_yuan);


fprintf('\n');
fprintf('====================================================\n');
fprintf('                   最优方案\n');
fprintf('====================================================\n');

fprintf('ComboID：%d\n',bestCombo);

fprintf('负载模型：%s\n', ...
    LoadModel(bestCombo));

fprintf('光伏模型：%s\n', ...
    PVModel(bestCombo));

fprintf('\n预测效果：\n');

fprintf('净负荷 MAE  = %.4f kW\n', ...
    Net_MAE(bestCombo));

fprintf('净负荷 RMSE = %.4f kW\n', ...
    Net_RMSE(bestCombo));

fprintf('净负荷 WAPE = %.4f %%\n', ...
    Net_WAPE(bestCombo));

fprintf('净负荷低估率 = %.4f %%\n', ...
    Net_UnderRate(bestCombo));

fprintf('\n调度效果：\n');

fprintf('计划购电量 = %.4f kWh\n', ...
    PlanEnergy_kWh(bestCombo));

fprintf('紧急购电量 = %.4f kWh\n', ...
    EmergencyEnergy_kWh(bestCombo));

fprintf('计划购电费 = %.4f 元\n', ...
    PlanCost_yuan(bestCombo));

fprintf('紧急购电费 = %.4f 元\n', ...
    EmergencyCost_yuan(bestCombo));

fprintf('全年总成本 = %.4f 元\n', ...
    bestCost);

fprintf('====================================================\n');


%% ============================================================
% 28. 4×4矩阵
%% ============================================================

costMatrix = ...
    zeros(4,4);

emergencyMatrix = ...
    zeros(4,4);

wapeMatrix = ...
    zeros(4,4);

underMatrix = ...
    zeros(4,4);


for c = 1:nCombo

    i = comboLoadIdx(c);
    j = comboPVIdx(c);

    costMatrix(i,j) = ...
        TotalCost_yuan(c);

    emergencyMatrix(i,j) = ...
        EmergencyEnergy_kWh(c);

    wapeMatrix(i,j) = ...
        Net_WAPE(c);

    underMatrix(i,j) = ...
        Net_UnderEnergy(c);

end


%% ============================================================
% 29. 总成本热力图
%% ============================================================

figure;

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
            'FontWeight','bold');

    end
end


%% ============================================================
% 30. 净负荷WAPE热力图
%% ============================================================

figure;

imagesc(wapeMatrix);

colorbar;

xticks(1:4);
yticks(1:4);

xticklabels(modelNames);
yticklabels(modelNames);

xlabel('光伏预测模型');
ylabel('负载预测模型');

title('16种组合净负荷 WAPE / %');

for i = 1:4

    for j = 1:4

        text( ...
            j,i, ...
            sprintf('%.2f',wapeMatrix(i,j)), ...
            'HorizontalAlignment','center');

    end
end


%% ============================================================
% 31. 紧急购电量热力图
%% ============================================================

figure;

imagesc(emergencyMatrix);

colorbar;

xticks(1:4);
yticks(1:4);

xticklabels(modelNames);
yticklabels(modelNames);

xlabel('光伏预测模型');
ylabel('负载预测模型');

title('16种组合紧急购电总量 / kWh');

for i = 1:4

    for j = 1:4

        text( ...
            j,i, ...
            sprintf('%.0f',emergencyMatrix(i,j)), ...
            'HorizontalAlignment','center');

    end
end


%% ============================================================
% 32. Excel
%% ============================================================

excelFile = fullfile( ...
    scriptDir, ...
    'Q2_tau08_02_16combo_results.xlsx');


if isfile(excelFile)
    delete(excelFile);
end


writetable( ...
    loadMetrics, ...
    excelFile, ...
    'Sheet','负载四模型误差');


writetable( ...
    pvMetrics, ...
    excelFile, ...
    'Sheet','光伏四模型误差');


writetable( ...
    netMetrics, ...
    excelFile, ...
    'Sheet','16组合预测指标');


writetable( ...
    summaryTable, ...
    excelFile, ...
    'Sheet','16组合最终结果');


writetable( ...
    summaryByCost, ...
    excelFile, ...
    'Sheet','总成本排名');


writeMatrixSheet( ...
    excelFile, ...
    '总成本矩阵', ...
    modelNames, ...
    costMatrix);


writeMatrixSheet( ...
    excelFile, ...
    '净负荷WAPE矩阵', ...
    modelNames, ...
    wapeMatrix);


writeMatrixSheet( ...
    excelFile, ...
    '紧急购电量矩阵', ...
    modelNames, ...
    emergencyMatrix);


%% ============================================================
% 33. 保存MAT
%% ============================================================

save( ...
    fullfile( ...
    scriptDir, ...
    'Q2_tau08_02_16combo_results.mat'), ...
    'predLoad','predPV', ...
    'loadMetrics','pvMetrics', ...
    'netMetrics', ...
    'summaryTable','summaryByCost', ...
    'costMatrix','emergencyMatrix', ...
    'wapeMatrix','underMatrix', ...
    'bestCombo','bestCost', ...
    'planGridAll','emergencyAll', ...
    'socStartAll','socEndAll', ...
    'tauL','tauPV', ...
    '-v7.3');


%% ============================================================
% 34. 清理断点
%% ============================================================

if isfile(predCheckpoint)
    delete(predCheckpoint);
end

if isfile(dispatchCheckpoint)
    delete(dispatchCheckpoint);
end


fprintf('\n');
fprintf('====================================================\n');
fprintf('全部完成\n');
fprintf('预测耗时：%.2f min\n',predictionTime/60);
fprintf('调度耗时：%.2f min\n',dispatchTime/60);
fprintf('\nExcel：\n%s\n',excelFile);
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

    sinWeek = sin(2*pi*(wd-1)/7);
    cosWeek = cos(2*pi*(wd-1)/7);

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

    doy = day(dates(d),'dayofyear');

    sinYear = sin(2*pi*(doy-1)/365);
    cosYear = cos(2*pi*(doy-1)/365);

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
%
% tau_L=0.8:
% 负载低估权重更高
%
% tau_PV=0.2:
% 光伏高估权重更高
%% ============================================================

function yPred = fitASRidge( ...
    Xtrain,Ytrain,Xtest, ...
    tau,lambda,maxIter,tol)

muX = mean(Xtrain,1);
sdX = std(Xtrain,0,1);

sdX(sdX<1e-10) = 1;

Xtr = (Xtrain-muX)./sdX;
Xte = (Xtest-muX)./sdX;

muY = mean(Ytrain);
sdY = std(Ytrain);

if sdY<1e-10
    sdY = 1;
end

y = (Ytrain-muY)/sdY;

X1 = [ones(size(Xtr,1),1),Xtr];
Xt = [ones(size(Xte,1),1),Xte];

p = size(X1,2);

R = eye(p);
R(1,1) = 0;

beta = ...
    (X1'*X1 + lambda*R) ...
    \ (X1'*y);

for iter = 1:maxIter

    e = y-X1*beta;

    % e>0：预测偏低
    w = (1-tau)*ones(size(e));
    w(e>=0) = tau;

    Xw = X1.*sqrt(w);
    yw = y.*sqrt(w);

    betaNew = ...
        (Xw'*Xw + lambda*R) ...
        \ (Xw'*yw);

    change = ...
        norm(betaNew-beta) / ...
        max(norm(beta),1e-8);

    beta = betaNew;

    if change<tol
        break;
    end
end

yPred = (Xt*beta)*sdY+muY;

end


%% ============================================================
% 函数6：SARIMA + 非对称残差分位数校正
%
% SARIMA(1,0,0)(1,0,0)[144]
%% ============================================================

function yPred = fitSARIMAQuantile( ...
    data,d,nTime,tau,windowDays)

firstDay = ...
    max(1,d-windowDays);

history = ...
    data(firstDay:(d-1),:);

nHistDays = ...
    size(history,1);

y = reshape(history.',[],1);

try

    % 非季节AR(1)
    % 季节AR(144)

    Mdl = arima( ...
        'Constant',NaN, ...
        'ARLags',1, ...
        'SARLags',nTime);

    EstMdl = estimate( ...
        Mdl,y, ...
        'Display','off');

    residual = infer( ...
        EstMdl,y);

    centerForecast = forecast( ...
        EstMdl,nTime, ...
        'Y0',y);


    %% 分时段残差分位数校正

    qShift = zeros(nTime,1);

    if length(residual)==nHistDays*nTime

        residualMat = reshape( ...
            residual,nTime,nHistDays)';

        globalR = residual(isfinite(residual));

        if isempty(globalR)
            globalQ = 0;
        else
            globalQ = quantile(globalR,tau);
        end

        for t = 1:nTime

            r = residualMat(:,t);
            r = r(isfinite(r));

            if length(r)>=5
                qShift(t) = quantile(r,tau);
            else
                qShift(t) = globalQ;
            end
        end

    else

        r = residual(isfinite(residual));

        if isempty(r)
            qShift(:) = 0;
        else
            qShift(:) = quantile(r,tau);
        end
    end

    yPred = centerForecast+qShift;


catch

    % SARIMA偶尔估计失败时：
    % 昨日同刻 + 历史变化分位数

    base = data(d-1,:)';

    firstErr = max(2,firstDay+1);

    if firstErr<=d-1

        delta = ...
            data(firstErr:(d-1),:) ...
            - data((firstErr-1):(d-2),:);

        shift = zeros(nTime,1);

        for t = 1:nTime

            r = delta(:,t);
            r = r(isfinite(r));

            if ~isempty(r)
                shift(t) = quantile(r,tau);
            end
        end

        yPred = base+shift;

    else
        yPred = base;
    end
end
end


%% ============================================================
% 函数7：预测评价指标
%% ============================================================

function T = evaluateForecast( ...
    actual,pred,tau,type,model)

a = actual(:);
p = pred(:);

e = p-a;

MAE = mean(abs(e));

RMSE = sqrt(mean(e.^2));

WAPE = ...
    100*sum(abs(e)) / ...
    max(sum(abs(a)),eps);

Bias = mean(e);

R = corr(a,p,'Rows','complete');

SSE = sum((a-p).^2);
SST = sum((a-mean(a)).^2);

R2 = 1-SSE/max(SST,eps);

UnderRate = ...
    100*mean(p<a);

OverRate = ...
    100*mean(p>a);

UnderEnergy = ...
    sum(max(a-p,0))*(10/60);

OverEnergy = ...
    sum(max(p-a,0))*(10/60);


%% Pinball

res = a-p;

L = zeros(size(res));

id = res>=0;

L(id)  = tau*res(id);
L(~id) = (1-tau)*(-res(~id));

PinballLoss = mean(L);


T = table( ...
    string(type), ...
    string(model), ...
    tau, ...
    MAE,RMSE,WAPE,Bias,R,R2, ...
    PinballLoss, ...
    UnderRate,OverRate, ...
    UnderEnergy,OverEnergy, ...
    'VariableNames',{ ...
    'Type', ...
    'Model', ...
    'Tau', ...
    'MAE_kW', ...
    'RMSE_kW', ...
    'WAPE_pct', ...
    'Bias_kW', ...
    'Correlation_R', ...
    'R2', ...
    'PinballLoss', ...
    'UnderRate_pct', ...
    'OverRate_pct', ...
    'UnderEnergy_kWh', ...
    'OverEnergy_kWh'});
end


%% ============================================================
% 函数8：每日计划购电LP
%% ============================================================

function plan = solveDailyPlanLP( ...
    Pload,Pv,price,Estart, ...
    dt,eta,Emin,Emax,Wmax,options)

N = length(price);

Wload = Pload(:)*dt;
Wv    = Pv(:)*dt;
price = price(:);

idxGrid = 1:N;
idxCh   = N+(1:N);
idxDis  = 2*N+(1:N);
idxCut  = 3*N+(1:N);
idxE    = 4*N+(1:N+1);

nvar = 5*N+1;

f = zeros(nvar,1);
f(idxGrid) = price;

Aeq = zeros(2*N+2,nvar);
beq = zeros(2*N+2,1);


%% 能量平衡

for t = 1:N

    Aeq(t,idxGrid(t)) = 1;
    Aeq(t,idxCh(t))   = -1;
    Aeq(t,idxDis(t))  = 1;
    Aeq(t,idxCut(t))  = -1;

    beq(t) = ...
        Wload(t)-Wv(t);
end


%% SOC动态

for t = 1:N

    row = N+t;

    Aeq(row,idxE(t))   = -1;
    Aeq(row,idxE(t+1)) = 1;

    Aeq(row,idxCh(t))  = -eta;

    Aeq(row,idxDis(t)) = 1/eta;
end


%% 初始SOC

Aeq(2*N+1,idxE(1)) = 1;
beq(2*N+1) = Estart;


%% 日计划终端SOC与起点相同

Aeq(2*N+2,idxE(end)) = 1;
beq(2*N+2) = Estart;


%% 上下界

lb = zeros(nvar,1);
ub = inf(nvar,1);

ub(idxCh)  = Wmax;
ub(idxDis) = Wmax;

ub(idxCut) = Wv;

lb(idxE) = Emin;
ub(idxE) = Emax;


%% 求解

[x,~,exitflag] = linprog( ...
    f,[],[], ...
    Aeq,beq, ...
    lb,ub, ...
    options);

if exitflag<=0
    error('每日计划LP求解失败');
end

plan.Wgrid = x(idxGrid);
plan.Wch   = x(idxCh);
plan.Wdis  = x(idxDis);
plan.Wcut  = x(idxCut);
plan.E     = x(idxE);

end


%% ============================================================
% 函数9：真实运行回放
%% ============================================================

function replay = replayActualDay( ...
    Pload,Pv,Wgrid,Estart, ...
    dt,eta,Emin,Emax,Wmax)

N = length(Wgrid);

Wload = Pload(:)*dt;
Wv    = Pv(:)*dt;

Wgrid = Wgrid(:);

Wch  = zeros(N,1);
Wdis = zeros(N,1);
Wem  = zeros(N,1);
Wcut = zeros(N,1);

E = zeros(N+1,1);

E(1) = Estart;


for t = 1:N

    balance = ...
        Wv(t) + ...
        Wgrid(t) - ...
        Wload(t);


    %% 富余

    if balance>=0

        capacityLimit = ...
            max( ...
            (Emax-E(t))/eta, ...
            0);

        Wch(t) = ...
            min([ ...
            balance, ...
            Wmax, ...
            capacityLimit]);

        E(t+1) = ...
            E(t)+eta*Wch(t);

        Wcut(t) = ...
            balance-Wch(t);


    %% 不足

    else

        deficit = -balance;

        socLimit = ...
            max( ...
            (E(t)-Emin)*eta, ...
            0);

        Wdis(t) = ...
            min([ ...
            deficit, ...
            Wmax, ...
            socLimit]);

        E(t+1) = ...
            E(t)-Wdis(t)/eta;

        Wem(t) = ...
            deficit-Wdis(t);
    end


    if E(t+1)<Emin && E(t+1)>Emin-1e-8
        E(t+1)=Emin;
    end

    if E(t+1)>Emax && E(t+1)<Emax+1e-8
        E(t+1)=Emax;
    end

end

replay.Wch  = Wch;
replay.Wdis = Wdis;
replay.Wem  = Wem;
replay.Wcut = Wcut;

replay.E = E;
replay.Eend = E(end);

end


%% ============================================================
% 函数10：矩阵写Excel
%% ============================================================

function writeMatrixSheet( ...
    excelFile,sheetName,modelNames,M)

T = table( ...
    modelNames(:), ...
    'VariableNames',{'LoadModel'});

for j = 1:length(modelNames)

    name = matlab.lang.makeValidName( ...
        "PV_"+modelNames(j));

    T.(name) = M(:,j);
end

writetable( ...
    T, ...
    excelFile, ...
    'Sheet',sheetName);

end