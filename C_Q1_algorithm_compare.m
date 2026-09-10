%% ============================================================
% 2026 C题 问题1 —— 不同优化算法比较
% 独立脚本，不修改 C_Q1.m
%
% 模型：
% 基于线性规划的微网日内购电与储能协同调度模型
%
% 比较：
% 1. linprog 默认算法
% 2. HiGHS 双单纯形法
% 3. 传统内点法
% 4. 传统双单纯形法
% 5. fmincon-SQP
%% ============================================================

clear;
clc;
close all;

fprintf('=============================================\n');
fprintf(' C题问题1：不同优化算法比较\n');
fprintf('=============================================\n\n');


%% ============================================================
% 1. 读取数据
%% ============================================================

filename = '附件1.xlsx';

T = readtable(filename, ...
    'VariableNamingRule','preserve');

% 附件1：
% 第1列：时间
% 第2列：电价 price（元/kWh）
% 第3列：小区负载功率（kW）
% 第4列：光伏预测功率（kW）

price = T{:,2};
Pload = T{:,3};
Pv    = T{:,4};

price = price(:);
Pload = Pload(:);
Pv    = Pv(:);

N = length(price);

fprintf('数据读取完成：%d 个时间段\n',N);


%% ============================================================
% 2. 功率转电量
%% ============================================================

dt = 10/60;      % 10 min = 1/6 h

Wload = Pload * dt;     % kWh
Wv    = Pv * dt;        % kWh


%% ============================================================
% 3. 储能参数
%% ============================================================

eta = 0.90;

E0   = 6000;       % 初始储电量 kWh
Emin = 1200;
Emax = 10800;

Pmax = 5000;       % kW

Wmax = Pmax * dt;  % 每10分钟最大充放电量

fprintf('每10分钟最大充放电量：%.4f kWh\n\n',Wmax);


%% ============================================================
% 4. 决策变量
%% ============================================================

% x =
%
% [Wgrid]
% [Wch]
% [Wdis]
% [Wcut]
% [E]
%
% Wgrid：N
% Wch  ：N
% Wdis ：N
% Wcut ：N
% E    ：N+1

idx_grid = 1:N;
idx_ch   = N + (1:N);
idx_dis  = 2*N + (1:N);
idx_cut  = 3*N + (1:N);
idx_E    = 4*N + (1:N+1);

nvar = 5*N + 1;

fprintf('决策变量总数：%d\n\n',nvar);


%% ============================================================
% 5. 目标函数
%% ============================================================

% min sum(price(t)*Wgrid(t))

f = zeros(nvar,1);

f(idx_grid) = price;


%% ============================================================
% 6. 等式约束
%% ============================================================

% 共：
% N 个电量平衡约束
% N 个储能状态转移约束
% 1 个初始储电量约束
% 1 个终止储电量约束

Aeq = zeros(2*N+2,nvar);
beq = zeros(2*N+2,1);


%% ---------- 6.1 电量平衡 ----------

% Wv + Wgrid + Wdis
% =
% Wload + Wch + Wcut
%
% 即：
%
% Wgrid - Wch + Wdis - Wcut
% =
% Wload - Wv

for t = 1:N

    Aeq(t,idx_grid(t)) = 1;

    Aeq(t,idx_ch(t)) = -1;

    Aeq(t,idx_dis(t)) = 1;

    Aeq(t,idx_cut(t)) = -1;

    beq(t) = Wload(t) - Wv(t);

end


%% ---------- 6.2 储能状态转移 ----------

% E(t+1)
% =
% E(t) + eta*Wch - Wdis/eta
%
% 整理：
%
% E(t+1)-E(t)-eta*Wch+Wdis/eta = 0

for t = 1:N

    row = N + t;

    Aeq(row,idx_E(t)) = -1;

    Aeq(row,idx_E(t+1)) = 1;

    Aeq(row,idx_ch(t)) = -eta;

    Aeq(row,idx_dis(t)) = 1/eta;

end


%% ---------- 6.3 0:00储电量 ----------

Aeq(2*N+1,idx_E(1)) = 1;

beq(2*N+1) = E0;


%% ---------- 6.4 24:00储电量 ----------

Aeq(2*N+2,idx_E(end)) = 1;

beq(2*N+2) = E0;


%% ============================================================
% 7. 不等式约束
%% ============================================================

A = [];
b = [];


%% ============================================================
% 8. 上下界
%% ============================================================

lb = zeros(nvar,1);

ub = inf(nvar,1);


% 外网购电
lb(idx_grid) = 0;


% 充电
lb(idx_ch) = 0;
ub(idx_ch) = Wmax;


% 放电
lb(idx_dis) = 0;
ub(idx_dis) = Wmax;


% 弃光
lb(idx_cut) = 0;


% 储能电量
lb(idx_E) = Emin;
ub(idx_E) = Emax;


%% ============================================================
% 9. 创建结果容器
%% ============================================================

Algorithm = {};
Cost = [];
GridEnergy = [];
MaxEqError = [];
RunTime = [];
ExitFlag = [];
BothChargeDischarge = [];


%% ============================================================
% 方法1：linprog 默认算法
%% ============================================================

fprintf('---------------------------------------------\n');
fprintf('方法1：linprog 默认算法\n');
fprintf('---------------------------------------------\n');

options1 = optimoptions( ...
    'linprog', ...
    'Display','none');

tic;

[x1,fval1,exitflag1] = linprog( ...
    f,A,b,Aeq,beq,lb,ub,options1);

time1 = toc;

if exitflag1 > 0

    Algorithm{end+1,1} = 'linprog-default';

    Cost(end+1,1) = fval1;

    GridEnergy(end+1,1) = ...
        sum(x1(idx_grid));

    MaxEqError(end+1,1) = ...
        max(abs(Aeq*x1-beq));

    RunTime(end+1,1) = time1;

    ExitFlag(end+1,1) = exitflag1;

    BothChargeDischarge(end+1,1) = ...
        sum(x1(idx_ch)>1e-6 & x1(idx_dis)>1e-6);

    fprintf('求解成功\n');
    fprintf('购电费：%.6f 元\n',fval1);
    fprintf('运行时间：%.6f s\n\n',time1);

else

    error('默认 linprog 求解失败！');

end


%% ============================================================
% 方法2：HiGHS 双单纯形
%% ============================================================

fprintf('---------------------------------------------\n');
fprintf('方法2：HiGHS 双单纯形法\n');
fprintf('---------------------------------------------\n');

try

    options2 = optimoptions( ...
        'linprog', ...
        'Algorithm','dual-simplex-highs', ...
        'Display','none');

    tic;

    [x2,fval2,exitflag2] = linprog( ...
        f,A,b,Aeq,beq,lb,ub,options2);

    time2 = toc;

    if exitflag2 > 0

        Algorithm{end+1,1} = ...
            'dual-simplex-highs';

        Cost(end+1,1) = fval2;

        GridEnergy(end+1,1) = ...
            sum(x2(idx_grid));

        MaxEqError(end+1,1) = ...
            max(abs(Aeq*x2-beq));

        RunTime(end+1,1) = time2;

        ExitFlag(end+1,1) = exitflag2;

        BothChargeDischarge(end+1,1) = ...
            sum(x2(idx_ch)>1e-6 & x2(idx_dis)>1e-6);

        fprintf('求解成功\n');
        fprintf('购电费：%.6f 元\n',fval2);
        fprintf('运行时间：%.6f s\n\n',time2);

    end

catch ME

    fprintf('当前版本不支持该算法，自动跳过。\n');
    fprintf('MATLAB信息：%s\n\n',ME.message);

end


%% ============================================================
% 方法3：传统内点法
%% ============================================================

fprintf('---------------------------------------------\n');
fprintf('方法3：内点法\n');
fprintf('---------------------------------------------\n');

try

    options3 = optimoptions( ...
        'linprog', ...
        'Algorithm','interior-point-legacy', ...
        'Display','none');

    tic;

    [x3,fval3,exitflag3] = linprog( ...
        f,A,b,Aeq,beq,lb,ub,options3);

    time3 = toc;

    if exitflag3 > 0

        Algorithm{end+1,1} = ...
            'interior-point-legacy';

        Cost(end+1,1) = fval3;

        GridEnergy(end+1,1) = ...
            sum(x3(idx_grid));

        MaxEqError(end+1,1) = ...
            max(abs(Aeq*x3-beq));

        RunTime(end+1,1) = time3;

        ExitFlag(end+1,1) = exitflag3;

        BothChargeDischarge(end+1,1) = ...
            sum(x3(idx_ch)>1e-6 & x3(idx_dis)>1e-6);

        fprintf('求解成功\n');
        fprintf('购电费：%.6f 元\n',fval3);
        fprintf('运行时间：%.6f s\n\n',time3);

    end

catch ME

    fprintf('当前版本不支持该算法，自动跳过。\n');
    fprintf('MATLAB信息：%s\n\n',ME.message);

end


%% ============================================================
% 方法4：传统双单纯形法
%% ============================================================

fprintf('---------------------------------------------\n');
fprintf('方法4：传统双单纯形法\n');
fprintf('---------------------------------------------\n');

try

    options4 = optimoptions( ...
        'linprog', ...
        'Algorithm','dual-simplex-legacy', ...
        'Display','none');

    tic;

    [x4,fval4,exitflag4] = linprog( ...
        f,A,b,Aeq,beq,lb,ub,options4);

    time4 = toc;

    if exitflag4 > 0

        Algorithm{end+1,1} = ...
            'dual-simplex-legacy';

        Cost(end+1,1) = fval4;

        GridEnergy(end+1,1) = ...
            sum(x4(idx_grid));

        MaxEqError(end+1,1) = ...
            max(abs(Aeq*x4-beq));

        RunTime(end+1,1) = time4;

        ExitFlag(end+1,1) = exitflag4;

        BothChargeDischarge(end+1,1) = ...
            sum(x4(idx_ch)>1e-6 & x4(idx_dis)>1e-6);

        fprintf('求解成功\n');
        fprintf('购电费：%.6f 元\n',fval4);
        fprintf('运行时间：%.6f s\n\n',time4);

    end

catch ME

    fprintf('当前版本不支持该算法，自动跳过。\n');
    fprintf('MATLAB信息：%s\n\n',ME.message);

end


%% ============================================================
% 方法5：fmincon-SQP
%% ============================================================

fprintf('---------------------------------------------\n');
fprintf('方法5：fmincon-SQP\n');
fprintf('---------------------------------------------\n');

try

    % 使用 linprog 已得到的可行最优解作为初始点
    x0 = x1;

    objective = @(x) f' * x;

    options5 = optimoptions( ...
        'fmincon', ...
        'Algorithm','sqp', ...
        'Display','none', ...
        'MaxIterations',1000, ...
        'OptimalityTolerance',1e-9, ...
        'ConstraintTolerance',1e-8, ...
        'StepTolerance',1e-10);

    tic;

    [x5,fval5,exitflag5] = fmincon( ...
        objective, ...
        x0, ...
        A,b, ...
        Aeq,beq, ...
        lb,ub, ...
        [], ...
        options5);

    time5 = toc;

    if exitflag5 > 0

        Algorithm{end+1,1} = ...
            'fmincon-SQP';

        Cost(end+1,1) = fval5;

        GridEnergy(end+1,1) = ...
            sum(x5(idx_grid));

        MaxEqError(end+1,1) = ...
            max(abs(Aeq*x5-beq));

        RunTime(end+1,1) = time5;

        ExitFlag(end+1,1) = exitflag5;

        BothChargeDischarge(end+1,1) = ...
            sum(x5(idx_ch)>1e-6 & x5(idx_dis)>1e-6);

        fprintf('求解成功\n');
        fprintf('购电费：%.6f 元\n',fval5);
        fprintf('运行时间：%.6f s\n\n',time5);

    end

catch ME

    fprintf('fmincon-SQP 求解失败，自动跳过。\n');
    fprintf('MATLAB信息：%s\n\n',ME.message);

end


%% ============================================================
% 10. 汇总结果
%% ============================================================

comparisonTable = table( ...
    Algorithm, ...
    Cost, ...
    GridEnergy, ...
    MaxEqError, ...
    RunTime, ...
    ExitFlag, ...
    BothChargeDischarge, ...
    'VariableNames', ...
    { ...
    'Algorithm', ...
    'Cost_Yuan', ...
    'GridEnergy_kWh', ...
    'MaxEqualityError', ...
    'RunTime_s', ...
    'ExitFlag', ...
    'SimultaneousChargeDischargePeriods' ...
    });


fprintf('\n');
fprintf('=============================================\n');
fprintf('          不同优化算法比较结果\n');
fprintf('=============================================\n');

disp(comparisonTable);


%% ============================================================
% 11. 与基准结果比较
%% ============================================================

baseCost = Cost(1);

CostDifference = Cost - baseCost;

RelativeError = ...
    abs(CostDifference) / abs(baseCost) * 100;

comparisonTable.CostDifference_Yuan = ...
    CostDifference;

comparisonTable.RelativeError_pct = ...
    RelativeError;


fprintf('\n与默认 linprog 相比：\n\n');

for i = 1:height(comparisonTable)

    fprintf('%-25s  ', ...
        comparisonTable.Algorithm{i});

    fprintf('成本差 = %.10f 元，', ...
        comparisonTable.CostDifference_Yuan(i));

    fprintf('相对误差 = %.10f %%\n', ...
        comparisonTable.RelativeError_pct(i));

end


%% ============================================================
% 12. 找运行时间最短算法
%% ============================================================

[bestTime,bestIndex] = ...
    min(comparisonTable.RunTime_s);

fprintf('\n=============================================\n');

fprintf('运行速度最快：%s\n', ...
    comparisonTable.Algorithm{bestIndex});

fprintf('运行时间：%.6f s\n',bestTime);

fprintf('=============================================\n');


%% ============================================================
% 13. 结果可靠性判断
%% ============================================================

maxCostDiff = ...
    max(abs(comparisonTable.CostDifference_Yuan));

fprintf('\n');

if maxCostDiff < 1e-3

    fprintf('结论：各算法所得最优购电费用基本一致。\n');

    fprintf('说明问题1优化结果具有较好的数值稳定性。\n');

else

    fprintf('警告：不同算法结果存在明显差异，需要进一步检查。\n');

end


%% ============================================================
% 14. 绘制算法运行时间比较图
%% ============================================================

figure;

bar(comparisonTable.RunTime_s);

xticks(1:height(comparisonTable));

xticklabels(comparisonTable.Algorithm);

xtickangle(20);

ylabel('运行时间 / s');

title('不同优化算法运行时间比较');

grid on;


%% ============================================================
% 15. 绘制购电费用比较图
%% ============================================================

figure;

bar(comparisonTable.Cost_Yuan);

xticks(1:height(comparisonTable));

xticklabels(comparisonTable.Algorithm);

xtickangle(20);

ylabel('全天购电费用 / 元');

title('不同优化算法购电费用比较');

grid on;


%% ============================================================
% 16. 保存结果
%% ============================================================

outputFile = ...
    'E:\数模\2026年正式比赛\CUMCM2026Problems\C题\算法比较.xlsx';

writetable( ...
    comparisonTable, ...
    outputFile);

fprintf('\n比较结果已经保存到：\n');
fprintf('%s\n',outputFile);