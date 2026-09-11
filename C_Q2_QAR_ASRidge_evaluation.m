%% ============================================================
% 2026 C题 问题2
%
% 最终预测模型：
%
% 负载：
% QAR
% tau_L = 0.80
%
% 光伏：
% AS-Ridge
% tau_PV = 0.20
%
% ------------------------------------------------------------
% 评价：
% MAE
% RMSE
% WAPE
% Bias
% Correlation R
% R^2
% Pinball Loss（负载QAR）
% 低估率
% 高估率
% 低估/高估电量
%
% ------------------------------------------------------------
% 80%预测区间：
%
% 负载QAR：
% 直接拟合 Q0.10 与 Q0.90
%
% 光伏AS-Ridge：
% 基于历史样本外残差经验分位数校准
%
% ------------------------------------------------------------
% 预测区间：
% 2025-02-01 ~ 2025-12-31
%
% expanding-window rolling forecast
%
%% ============================================================

clear;
clc;
close all;

rng(20260911,'twister');

fprintf('====================================================\n');
fprintf(' C题问题2 最终预测模型\n');
fprintf(' 负载：QAR，tau_L = 0.80\n');
fprintf(' 光伏：AS-Ridge，tau_PV = 0.20\n');
fprintf('====================================================\n\n');


%% ============================================================
% 1. 参数
%% ============================================================

tauL = 0.80;

tauPV = 0.20;


%% 80%预测区间

PIlevel = 0.80;

tauLower = 0.10;

tauUpper = 0.90;


%% AS-Ridge参数

lambdaAS = 1e-3;

maxIterAS = 50;

tolAS = 1e-6;


fprintf('负载QAR tau_L = %.2f\n',tauL);

fprintf('光伏AS-Ridge 非对称参数 = %.2f\n',tauPV);

fprintf('预测区间 = %.0f%%\n\n',PIlevel*100);


%% ============================================================
% 2. 文件
%% ============================================================

scriptDir = ...
    fileparts(mfilename('fullpath'));


if isempty(scriptDir)

    scriptDir = pwd;

end


dataFile = ...
    fullfile( ...
    scriptDir, ...
    '附件2.xlsx');


if ~isfile(dataFile)

    error('找不到附件2.xlsx');

end


%% ============================================================
% 3. 读取数据
%% ============================================================

load_data = ...
    readmatrix( ...
    dataFile, ...
    'Sheet','小区负载', ...
    'Range','B2:EO366');


pv_data = ...
    readmatrix( ...
    dataFile, ...
    'Sheet','光伏发电实际功率', ...
    'Range','B2:EO366');


[nDay,nTime] = ...
    size(load_data);


if nDay~=365 || nTime~=144

    error('数据尺寸不是365×144');

end


if ~isequal(size(load_data),size(pv_data))

    error('负载与光伏数据尺寸不一致');

end


if any(isnan(load_data),'all') || ...
   any(isnan(pv_data),'all')

    error('数据存在NaN');

end


fprintf('数据读取完成：365 × 144\n\n');


%% ============================================================
% 4. 日期
%% ============================================================

dates = ...
    (datetime(2025,1,1):days(1):datetime(2025,12,31))';


%% ============================================================
% 5. 正式预测日期
%% ============================================================

startDay = 32;

endDay = 365;


predDays = ...
    startDay:endDay;


nPredDay = ...
    length(predDays);


predDates = ...
    dates(predDays);


actualLoad = ...
    load_data(predDays,:);


actualPV = ...
    pv_data(predDays,:);


fprintf('预测日期：%s ~ %s\n', ...
    string(predDates(1)), ...
    string(predDates(end)));


fprintf('预测天数：%d\n\n',nPredDay);


%% ============================================================
% 6. 初始化
%% ============================================================

%% 负载 QAR Q0.8

predLoad = ...
    nan(nPredDay,nTime);


%% 负载预测区间 Q0.1~Q0.9

loadLower = ...
    nan(nPredDay,nTime);


loadUpper = ...
    nan(nPredDay,nTime);


%% 光伏 AS-Ridge

predPV = ...
    nan(nPredDay,nTime);


%% 光伏经验预测区间

pvLower = ...
    nan(nPredDay,nTime);


pvUpper = ...
    nan(nPredDay,nTime);


%% ============================================================
% 7. QAR参数
%% ============================================================

lambdaQAR = ...
    1e-8;


if exist('fitrqlinear','file')~=2

    error('缺少 fitrqlinear');

end


%% ============================================================
% 8. 断点
%% ============================================================

checkpointFile = ...
    fullfile( ...
    scriptDir, ...
    'QAR_ASRidge_tau08_02_checkpoint.mat');


lastFinished = ...
    0;


if isfile(checkpointFile)


    S = ...
        load(checkpointFile);


    if isfield(S,'lastFinished') && ...
       isfield(S,'predLoad') && ...
       isfield(S,'predPV') && ...
       isfield(S,'tauL') && ...
       isfield(S,'tauPV') && ...
       abs(S.tauL-tauL)<1e-12 && ...
       abs(S.tauPV-tauPV)<1e-12


        predLoad = ...
            S.predLoad;


        loadLower = ...
            S.loadLower;


        loadUpper = ...
            S.loadUpper;


        predPV = ...
            S.predPV;


        pvLower = ...
            S.pvLower;


        pvUpper = ...
            S.pvUpper;


        lastFinished = ...
            S.lastFinished;


        fprintf( ...
            '恢复断点：%d/%d\n\n', ...
            lastFinished,nPredDay);


    end

end


%% ============================================================
% 9. 全年滚动预测
%% ============================================================

ticMain = ...
    tic;


for k = ...
        (lastFinished+1):nPredDay


    d = ...
        predDays(k);


    fprintf( ...
        '[%03d/%03d] %s\n', ...
        k,nPredDay,string(dates(d)));


    %% --------------------------------------------------------
    % 最大lag=14
    %% --------------------------------------------------------

    trainDays = ...
        15:(d-1);


    %% ========================================================
    % 9.1 负载QAR特征
    %
    % d-1
    % d-7
    % d-14
    %% ========================================================

    [XLtrain,YLtrain] = ...
        buildLoadQAR( ...
        load_data, ...
        trainDays, ...
        nTime);


    [XLtest,~] = ...
        buildLoadQAR( ...
        load_data, ...
        d, ...
        nTime);


    %% ========================================================
    % 9.2 负载 Q0.80
    %% ========================================================

    mdlLoad = ...
        fitrqlinear( ...
        XLtrain, ...
        YLtrain, ...
        Quantiles=tauL, ...
        Lambda=lambdaQAR, ...
        Standardize=true, ...
        Solver="bfgs");


    y = ...
        predict( ...
        mdlLoad, ...
        XLtest);


    predLoad(k,:) = ...
        max(y,0)';


    %% ========================================================
    % 9.3 负载 Q0.10
    %% ========================================================

    mdlLoadLow = ...
        fitrqlinear( ...
        XLtrain, ...
        YLtrain, ...
        Quantiles=tauLower, ...
        Lambda=lambdaQAR, ...
        Standardize=true, ...
        Solver="bfgs");


    yLow = ...
        predict( ...
        mdlLoadLow, ...
        XLtest);


    %% ========================================================
    % 9.4 负载 Q0.90
    %% ========================================================

    mdlLoadHigh = ...
        fitrqlinear( ...
        XLtrain, ...
        YLtrain, ...
        Quantiles=tauUpper, ...
        Lambda=lambdaQAR, ...
        Standardize=true, ...
        Solver="bfgs");


    yHigh = ...
        predict( ...
        mdlLoadHigh, ...
        XLtest);


    lo = ...
        min(yLow,yHigh);


    hi = ...
        max(yLow,yHigh);


    loadLower(k,:) = ...
        max(lo,0)';


    loadUpper(k,:) = ...
        max(hi,0)';


    %% ========================================================
    % 9.5 光伏AS-Ridge特征
    %
    % d-1
    % d-2
    % d-3
    % d-7
    % d-14
    % 日内sin/cos
    % 年周期sin/cos
    %% ========================================================

    [XPtrain,YPTrain] = ...
        buildPVRich( ...
        pv_data, ...
        dates, ...
        trainDays, ...
        nTime);


    [XPtest,~] = ...
        buildPVRich( ...
        pv_data, ...
        dates, ...
        d, ...
        nTime);


    %% ========================================================
    % 9.6 光伏AS-Ridge主预测
    %% ========================================================

    [pvPrediction,betaAS,scaleInfo] = ...
        fitASRidge( ...
        XPtrain, ...
        YPTrain, ...
        XPtest, ...
        tauPV, ...
        lambdaAS, ...
        maxIterAS, ...
        tolAS);


    predPV(k,:) = ...
        max(pvPrediction,0)';


    %% ========================================================
    % 9.7 光伏AS-Ridge历史残差
    %
    % 用训练数据拟合值构造经验预测区间
    %% ========================================================

    pvTrainFit = ...
        predictASRidgeFromFit( ...
        XPtrain, ...
        betaAS, ...
        scaleInfo);


    residualTrain = ...
        YPTrain-pvTrainFit;


    %% --------------------------------------------------------
    % 为避免未来信息泄漏：
    %
    % 预测第d天时，
    % 区间只使用d-1之前训练样本的残差
    %% --------------------------------------------------------

    rLow = ...
        quantile( ...
        residualTrain, ...
        tauLower);


    rHigh = ...
        quantile( ...
        residualTrain, ...
        tauUpper);


    pvLower(k,:) = ...
        max( ...
        pvPrediction+rLow, ...
        0)';


    pvUpper(k,:) = ...
        max( ...
        pvPrediction+rHigh, ...
        0)';


    %% --------------------------------------------------------
    % 保证上下界顺序
    %% --------------------------------------------------------

    tempLow = ...
        min( ...
        pvLower(k,:), ...
        pvUpper(k,:));


    tempHigh = ...
        max( ...
        pvLower(k,:), ...
        pvUpper(k,:));


    pvLower(k,:) = ...
        tempLow;


    pvUpper(k,:) = ...
        tempHigh;


    %% ========================================================
    % 保存
    %% ========================================================

    lastFinished = ...
        k;


    if mod(k,7)==0 || ...
       k==nPredDay


        save( ...
            checkpointFile, ...
            'predLoad', ...
            'loadLower', ...
            'loadUpper', ...
            'predPV', ...
            'pvLower', ...
            'pvUpper', ...
            'lastFinished', ...
            'tauL', ...
            'tauPV', ...
            '-v7.3');


    end


end


runtime = ...
    toc(ticMain);


fprintf('\n');

fprintf('预测完成：%.2f min\n\n', ...
    runtime/60);


%% ============================================================
% 10. 负载QAR评价
%% ============================================================

loadMetrics = ...
    evaluateForecast( ...
    actualLoad, ...
    predLoad, ...
    loadLower, ...
    loadUpper, ...
    PIlevel, ...
    "负载", ...
    "QAR");


%% QAR Pinball Loss

loadPinball = ...
    calculatePinball( ...
    actualLoad, ...
    predLoad, ...
    tauL);


loadMetrics.Tau = ...
    tauL;


loadMetrics.PinballLoss = ...
    loadPinball;


fprintf('\n');

fprintf('====================================================\n');

fprintf('       负载 QAR tau=0.80 模型评价\n');

fprintf('====================================================\n');


disp(loadMetrics);


%% ============================================================
% 11. 光伏AS-Ridge评价
%% ============================================================

pvMetrics = ...
    evaluateForecast( ...
    actualPV, ...
    predPV, ...
    pvLower, ...
    pvUpper, ...
    PIlevel, ...
    "光伏", ...
    "AS-Ridge");


pvMetrics.AsymmetryParameter = ...
    tauPV;


fprintf('\n');

fprintf('====================================================\n');

fprintf('     光伏 AS-Ridge tau=0.20 模型评价\n');

fprintf('====================================================\n');


disp(pvMetrics);


%% ============================================================
% 12. 光伏有效发电时段
%% ============================================================

thresholdPV = ...
    10;


maskPV = ...
    actualPV>thresholdPV;


aPV = ...
    actualPV(maskPV);


pPV = ...
    predPV(maskPV);


PVActive_MAE = ...
    mean(abs(pPV-aPV));


PVActive_RMSE = ...
    sqrt(mean((pPV-aPV).^2));


PVActive_WAPE = ...
    100 ...
    * sum(abs(pPV-aPV)) ...
    / max(sum(abs(aPV)),eps);


PVActive_Bias = ...
    mean(pPV-aPV);


PVActive_UnderRate = ...
    100 ...
    * mean(pPV<aPV);


PVActive_OverRate = ...
    100 ...
    * mean(pPV>aPV);


pvActiveMetrics = ...
    table( ...
    thresholdPV, ...
    length(aPV), ...
    PVActive_MAE, ...
    PVActive_RMSE, ...
    PVActive_WAPE, ...
    PVActive_Bias, ...
    PVActive_UnderRate, ...
    PVActive_OverRate, ...
    'VariableNames',{ ...
    'Threshold_kW', ...
    'Samples', ...
    'MAE_kW', ...
    'RMSE_kW', ...
    'WAPE_pct', ...
    'Bias_kW', ...
    'UnderRate_pct', ...
    'OverRate_pct'});


fprintf('\n');

fprintf('========== 光伏有效发电时段 ==========\n');

disp(pvActiveMetrics);


%% ============================================================
% 13. 月度评价
%% ============================================================

monthlyLoad = ...
    calculateMonthlyMetrics( ...
    actualLoad, ...
    predLoad, ...
    predDates, ...
    "Load-QAR");


monthlyPV = ...
    calculateMonthlyMetrics( ...
    actualPV, ...
    predPV, ...
    predDates, ...
    "PV-AS-Ridge");


%% ============================================================
% 14. 典型日
%% ============================================================

targetDate = ...
    datetime(2025,3,20);


idDay = ...
    find(predDates==targetDate);


timeHour = ...
    (0:nTime-1)/6;


%% ============================================================
% 15. 负载典型日
%% ============================================================

if ~isempty(idDay)


    figure;


    plot( ...
        timeHour, ...
        actualLoad(idDay,:), ...
        'LineWidth',1.8);


    hold on;


    plot( ...
        timeHour, ...
        predLoad(idDay,:), ...
        '--', ...
        'LineWidth',1.8);


    xlabel('时间 / h');

    ylabel('负载功率 / kW');


    title( ...
        '负载QAR：实际值与Q_{0.8}预测值');


    legend( ...
        '实际值', ...
        'QAR预测', ...
        'Location','best');


    grid on;


end


%% ============================================================
% 16. 负载80%预测区间
%% ============================================================

if ~isempty(idDay)


    figure;


    x = ...
        timeHour;


    fill( ...
        [x fliplr(x)], ...
        [ ...
        loadLower(idDay,:) ...
        fliplr(loadUpper(idDay,:))], ...
        [0.85 0.85 0.85], ...
        'EdgeColor','none', ...
        'FaceAlpha',0.5);


    hold on;


    plot( ...
        x, ...
        actualLoad(idDay,:), ...
        'LineWidth',1.8);


    plot( ...
        x, ...
        predLoad(idDay,:), ...
        '--', ...
        'LineWidth',1.8);


    xlabel('时间 / h');

    ylabel('负载功率 / kW');


    title('负载QAR 80%预测区间');


    legend( ...
        '80%预测区间', ...
        '实际值', ...
        'Q_{0.8}预测', ...
        'Location','best');


    grid on;


end


%% ============================================================
% 17. 光伏典型日
%% ============================================================

if ~isempty(idDay)


    figure;


    plot( ...
        timeHour, ...
        actualPV(idDay,:), ...
        'LineWidth',1.8);


    hold on;


    plot( ...
        timeHour, ...
        predPV(idDay,:), ...
        '--', ...
        'LineWidth',1.8);


    xlabel('时间 / h');

    ylabel('光伏功率 / kW');


    title( ...
        '光伏AS-Ridge：实际值与预测值');


    legend( ...
        '实际值', ...
        'AS-Ridge预测', ...
        'Location','best');


    grid on;


end


%% ============================================================
% 18. 光伏80%预测区间
%% ============================================================

if ~isempty(idDay)


    figure;


    x = ...
        timeHour;


    fill( ...
        [x fliplr(x)], ...
        [ ...
        pvLower(idDay,:) ...
        fliplr(pvUpper(idDay,:))], ...
        [0.85 0.85 0.85], ...
        'EdgeColor','none', ...
        'FaceAlpha',0.5);


    hold on;


    plot( ...
        x, ...
        actualPV(idDay,:), ...
        'LineWidth',1.8);


    plot( ...
        x, ...
        predPV(idDay,:), ...
        '--', ...
        'LineWidth',1.8);


    xlabel('时间 / h');

    ylabel('光伏功率 / kW');


    title('光伏AS-Ridge 80%预测区间');


    legend( ...
        '80%预测区间', ...
        '实际值', ...
        'AS-Ridge预测', ...
        'Location','best');


    grid on;


end


%% ============================================================
% 19. 负载拟合散点图
%% ============================================================

figure;


scatter( ...
    actualLoad(:), ...
    predLoad(:), ...
    8, ...
    'filled');


hold on;


lims = [ ...
    min([actualLoad(:);predLoad(:)]), ...
    max([actualLoad(:);predLoad(:)])];


plot( ...
    lims,lims, ...
    'k--', ...
    'LineWidth',1.5);


xlabel('实际负载 / kW');

ylabel('QAR预测负载 / kW');


title( ...
    sprintf( ...
    '负载QAR拟合效果，R^2=%.4f', ...
    loadMetrics.R2));


axis equal;

xlim(lims);

ylim(lims);

grid on;


%% ============================================================
% 20. 光伏拟合散点图
%% ============================================================

figure;


scatter( ...
    actualPV(:), ...
    predPV(:), ...
    8, ...
    'filled');


hold on;


lims = [ ...
    min([actualPV(:);predPV(:)]), ...
    max([actualPV(:);predPV(:)])];


plot( ...
    lims,lims, ...
    'k--', ...
    'LineWidth',1.5);


xlabel('实际光伏 / kW');

ylabel('AS-Ridge预测光伏 / kW');


title( ...
    sprintf( ...
    '光伏AS-Ridge拟合效果，R^2=%.4f', ...
    pvMetrics.R2));


axis equal;

xlim(lims);

ylim(lims);

grid on;


%% ============================================================
% 21. 负载残差
%% ============================================================

figure;


histogram( ...
    actualLoad(:)-predLoad(:), ...
    60, ...
    'Normalization','probability');


xlabel('实际值 - 预测值 / kW');

ylabel('概率');


title('负载QAR残差分布');


grid on;


%% ============================================================
% 22. 光伏残差
%% ============================================================

figure;


histogram( ...
    actualPV(:)-predPV(:), ...
    60, ...
    'Normalization','probability');


xlabel('实际值 - 预测值 / kW');

ylabel('概率');


title('光伏AS-Ridge残差分布');


grid on;


%% ============================================================
% 23. 输出Excel
%% ============================================================

excelFile = ...
    fullfile( ...
    scriptDir, ...
    'Q2_QAR_ASRidge_prediction_evaluation.xlsx');


if isfile(excelFile)

    delete(excelFile);

end


writetable( ...
    loadMetrics, ...
    excelFile, ...
    'Sheet','负载QAR评价');


writetable( ...
    pvMetrics, ...
    excelFile, ...
    'Sheet','光伏ASRidge评价');


writetable( ...
    pvActiveMetrics, ...
    excelFile, ...
    'Sheet','光伏有效时段评价');


writetable( ...
    monthlyLoad, ...
    excelFile, ...
    'Sheet','负载月度评价');


writetable( ...
    monthlyPV, ...
    excelFile, ...
    'Sheet','光伏月度评价');


%% ============================================================
% 24. 保存预测
%% ============================================================

save( ...
    fullfile( ...
    scriptDir, ...
    'Q2_QAR_ASRidge_predictions.mat'), ...
    'predLoad', ...
    'predPV', ...
    'loadLower', ...
    'loadUpper', ...
    'pvLower', ...
    'pvUpper', ...
    'actualLoad', ...
    'actualPV', ...
    'loadMetrics', ...
    'pvMetrics', ...
    'tauL', ...
    'tauPV', ...
    'predDates', ...
    '-v7.3');


%% ============================================================
% 25. 删除断点
%% ============================================================

if isfile(checkpointFile)

    delete(checkpointFile);

end


fprintf('\n');

fprintf('====================================================\n');

fprintf('全部完成\n');

fprintf('负载：QAR tau=0.8\n');

fprintf('光伏：AS-Ridge tau=0.2\n');

fprintf('Excel：%s\n',excelFile);

fprintf('====================================================\n');


%% ============================================================
% 函数1：负载QAR
%% ============================================================

function [X,Y] = buildLoadQAR( ...
    data,dayList,nTime)


dayList = ...
    dayList(:)';


X = ...
    zeros( ...
    length(dayList)*nTime, ...
    3);


Y = ...
    zeros( ...
    length(dayList)*nTime, ...
    1);


r = 1;


for d = dayList


    rows = ...
        r:(r+nTime-1);


    X(rows,1) = ...
        data(d-1,:)';


    X(rows,2) = ...
        data(d-7,:)';


    X(rows,3) = ...
        data(d-14,:)';


    Y(rows) = ...
        data(d,:)';


    r = ...
        r+nTime;


end


end


%% ============================================================
% 函数2：光伏AS-Ridge丰富特征
%% ============================================================

function [X,Y] = buildPVRich( ...
    data,dates,dayList,nTime)


dayList = ...
    dayList(:)';


X = ...
    zeros( ...
    length(dayList)*nTime, ...
    9);


Y = ...
    zeros( ...
    length(dayList)*nTime, ...
    1);


slot = ...
    (0:nTime-1)';


sinDay = ...
    sin(2*pi*slot/nTime);


cosDay = ...
    cos(2*pi*slot/nTime);


r = 1;


for d = dayList


    doy = ...
        day( ...
        dates(d), ...
        'dayofyear');


    sinYear = ...
        sin( ...
        2*pi*(doy-1)/365);


    cosYear = ...
        cos( ...
        2*pi*(doy-1)/365);


    rows = ...
        r:(r+nTime-1);


    X(rows,1) = ...
        data(d-1,:)';


    X(rows,2) = ...
        data(d-2,:)';


    X(rows,3) = ...
        data(d-3,:)';


    X(rows,4) = ...
        data(d-7,:)';


    X(rows,5) = ...
        data(d-14,:)';


    X(rows,6) = ...
        sinDay;


    X(rows,7) = ...
        cosDay;


    X(rows,8) = ...
        sinYear;


    X(rows,9) = ...
        cosYear;


    Y(rows) = ...
        data(d,:)';


    r = ...
        r+nTime;


end


end


%% ============================================================
% 函数3：AS-Ridge训练
%
% 非对称平方损失 + Ridge
%
% 注意：
% 这里的tau是非对称权重参数，
% 严格来说对应expectile思想，
% 不是条件quantile。
%% ============================================================

function [yPred,beta,scaleInfo] = ...
    fitASRidge( ...
    Xtrain,Ytrain,Xtest, ...
    tau,lambda,maxIter,tol)


%% 标准化X

muX = ...
    mean(Xtrain,1);


sdX = ...
    std(Xtrain,0,1);


sdX(sdX<1e-10) = ...
    1;


Xtr = ...
    (Xtrain-muX)./sdX;


Xte = ...
    (Xtest-muX)./sdX;


%% 标准化Y

muY = ...
    mean(Ytrain);


sdY = ...
    std(Ytrain);


if sdY<1e-10

    sdY = 1;

end


y = ...
    (Ytrain-muY)/sdY;


%% 添加截距

X1 = ...
    [ ...
    ones(size(Xtr,1),1), ...
    Xtr];


Xt = ...
    [ ...
    ones(size(Xte,1),1), ...
    Xte];


p = ...
    size(X1,2);


%% Ridge矩阵

RidgeMat = ...
    eye(p);


RidgeMat(1,1) = ...
    0;


%% 初始普通Ridge

beta = ...
    ( ...
    X1'*X1 ...
    + lambda*RidgeMat) ...
    \ ...
    (X1'*y);


%% IRLS

for iter = 1:maxIter


    e = ...
        y-X1*beta;


    % e>0：
    % 实际值>预测值，即低估
    %
    % tau=0.2时：
    % 低估权重0.2
    % 高估权重0.8
    %
    % 因而重点抑制光伏高估

    w = ...
        (1-tau) ...
        * ones(size(e));


    w(e>=0) = ...
        tau;


    Xw = ...
        X1 ...
        .* sqrt(w);


    yw = ...
        y ...
        .* sqrt(w);


    betaNew = ...
        ( ...
        Xw'*Xw ...
        + lambda*RidgeMat) ...
        \ ...
        (Xw'*yw);


    change = ...
        norm(betaNew-beta) ...
        / max(norm(beta),1e-8);


    beta = ...
        betaNew;


    if change<tol

        break;

    end


end


%% 预测

yPredStd = ...
    Xt*beta;


yPred = ...
    yPredStd*sdY ...
    + muY;


%% 保存标准化信息

scaleInfo.muX = ...
    muX;


scaleInfo.sdX = ...
    sdX;


scaleInfo.muY = ...
    muY;


scaleInfo.sdY = ...
    sdY;


end


%% ============================================================
% 函数4：利用已经训练好的AS-Ridge计算训练拟合值
%% ============================================================

function yFit = ...
    predictASRidgeFromFit( ...
    X,beta,scaleInfo)


Xstd = ...
    ( ...
    X-scaleInfo.muX) ...
    ./ scaleInfo.sdX;


X1 = ...
    [ ...
    ones(size(Xstd,1),1), ...
    Xstd];


yFitStd = ...
    X1*beta;


yFit = ...
    yFitStd ...
    * scaleInfo.sdY ...
    + scaleInfo.muY;


end


%% ============================================================
% 函数5：统一预测评价
%% ============================================================

function T = evaluateForecast( ...
    actual,pred,lower,upper, ...
    PIlevel,type,model)


a = ...
    actual(:);


p = ...
    pred(:);


e = ...
    p-a;


%% MAE

MAE = ...
    mean(abs(e));


%% RMSE

RMSE = ...
    sqrt(mean(e.^2));


%% WAPE

WAPE = ...
    100 ...
    * sum(abs(e)) ...
    / max(sum(abs(a)),eps);


%% Bias

Bias = ...
    mean(e);


%% 相关系数

R = ...
    corr( ...
    a,p, ...
    'Rows','complete');


%% R2

SSE = ...
    sum((a-p).^2);


SST = ...
    sum( ...
    (a-mean(a)).^2);


R2 = ...
    1 ...
    - SSE/max(SST,eps);


%% 低估率

UnderRate = ...
    100 ...
    * mean(p<a);


%% 高估率

OverRate = ...
    100 ...
    * mean(p>a);


%% 相等率

EqualRate = ...
    100 ...
    - UnderRate ...
    - OverRate;


%% 电量

dt = ...
    10/60;


UnderEnergy = ...
    sum(max(a-p,0)) ...
    * dt;


OverEnergy = ...
    sum(max(p-a,0)) ...
    * dt;


%% PICP

low = ...
    lower(:);


up = ...
    upper(:);


inside = ...
    a>=low ...
    & a<=up;


PICP = ...
    100 ...
    * mean(inside);


%% MPIW

MPIW = ...
    mean(up-low);


%% NMPIW

rangeY = ...
    max(a)-min(a);


NMPIW = ...
    100 ...
    * MPIW ...
    / max(rangeY,eps);


T = ...
    table( ...
    string(type), ...
    string(model), ...
    MAE, ...
    RMSE, ...
    WAPE, ...
    Bias, ...
    R, ...
    R2, ...
    UnderRate, ...
    OverRate, ...
    EqualRate, ...
    UnderEnergy, ...
    OverEnergy, ...
    PIlevel*100, ...
    PICP, ...
    MPIW, ...
    NMPIW, ...
    'VariableNames',{ ...
    'Type', ...
    'Model', ...
    'MAE_kW', ...
    'RMSE_kW', ...
    'WAPE_pct', ...
    'Bias_kW', ...
    'Correlation_R', ...
    'R2', ...
    'UnderRate_pct', ...
    'OverRate_pct', ...
    'EqualRate_pct', ...
    'UnderEnergy_kWh', ...
    'OverEnergy_kWh', ...
    'PI_Nominal_pct', ...
    'PI_Coverage_pct', ...
    'MPIW_kW', ...
    'NMPIW_pct'});


end


%% ============================================================
% 函数6：Pinball Loss
%% ============================================================

function Lmean = ...
    calculatePinball(actual,pred,tau)


r = ...
    actual(:)-pred(:);


L = ...
    zeros(size(r));


id = ...
    r>=0;


L(id) = ...
    tau*r(id);


L(~id) = ...
    (1-tau)*(-r(~id));


Lmean = ...
    mean(L);


end


%% ============================================================
% 函数7：月度评价
%% ============================================================

function T = ...
    calculateMonthlyMetrics( ...
    actual,pred,predDates,type)


months = ...
    unique(month(predDates));


n = ...
    length(months);


Month = ...
    zeros(n,1);


MAE = ...
    zeros(n,1);


RMSE = ...
    zeros(n,1);


WAPE = ...
    zeros(n,1);


Bias = ...
    zeros(n,1);


R2 = ...
    zeros(n,1);


UnderRate = ...
    zeros(n,1);


OverRate = ...
    zeros(n,1);


for k = 1:n


    m = ...
        months(k);


    id = ...
        month(predDates)==m;


    a = ...
        actual(id,:);


    p = ...
        pred(id,:);


    a = ...
        a(:);


    p = ...
        p(:);


    e = ...
        p-a;


    Month(k) = ...
        m;


    MAE(k) = ...
        mean(abs(e));


    RMSE(k) = ...
        sqrt(mean(e.^2));


    WAPE(k) = ...
        100 ...
        * sum(abs(e)) ...
        / max(sum(abs(a)),eps);


    Bias(k) = ...
        mean(e);


    SSE = ...
        sum((a-p).^2);


    SST = ...
        sum( ...
        (a-mean(a)).^2);


    R2(k) = ...
        1 ...
        - SSE/max(SST,eps);


    UnderRate(k) = ...
        100 ...
        * mean(p<a);


    OverRate(k) = ...
        100 ...
        * mean(p>a);


end


Type = ...
    repmat( ...
    string(type), ...
    n,1);


T = ...
    table( ...
    Type, ...
    Month, ...
    MAE, ...
    RMSE, ...
    WAPE, ...
    Bias, ...
    R2, ...
    UnderRate, ...
    OverRate, ...
    'VariableNames',{ ...
    'Type', ...
    'Month', ...
    'MAE_kW', ...
    'RMSE_kW', ...
    'WAPE_pct', ...
    'Bias_kW', ...
    'R2', ...
    'UnderRate_pct', ...
    'OverRate_pct'});


end