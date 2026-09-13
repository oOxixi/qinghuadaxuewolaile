% 2026 数模 C题问题1：微网全天计划购电与储能调度
% 附件1的最后一行是次日0:00。问题1按日周期处理，因此先移到当天首行。

clear;
clc;
close all;

%% 数据读取
rootDir = fileparts(mfilename('fullpath'));
dataFile = fullfile(rootDir, 'data', '附件1.xlsx');
supportDir = fullfile(rootDir, '支撑材料');

data = readtable(dataFile, 'VariableNamingRule', 'preserve');
priceRaw = data{:, 2};
PloadRaw = data{:, 3};
PvRaw = data{:, 4};

priceRaw = priceRaw(:);
PloadRaw = PloadRaw(:);
PvRaw = PvRaw(:);
N = numel(priceRaw);

if N ~= 144
    error('附件1应包含144个10分钟时段，请检查数据。');
end

% 原顺序为0:10,...,23:50,次日0:00，模型内部改为0:00,...,23:50
price = [priceRaw(end); priceRaw(1:end-1)];
Pload = [PloadRaw(end); PloadRaw(1:end-1)];
Pv = [PvRaw(end); PvRaw(1:end-1)];

dt = 10/60;
Wload = Pload*dt;
Wv = Pv*dt;

fprintf('已读取 %d 个10分钟时段，时间轴从0:00开始。\n', N);

%% 优化模型
eta = 0.90;
E0 = 6000;
Emin = 1200;
Emax = 10800;
Wmax = 5000*dt;

% x = [Wgrid; Wch; Wdis; Wcut; E]
idxGrid = 1:N;
idxCh = N + (1:N);
idxDis = 2*N + (1:N);
idxCut = 3*N + (1:N);
idxE = 4*N + (1:N+1);
nVar = 5*N + 1;

% 目标函数：全天外网购电费用最小
f = zeros(nVar, 1);
f(idxGrid) = price;

% 每个时段有一个电量平衡方程和一个储能状态方程，另加首尾SOC
Aeq = zeros(2*N + 2, nVar);
beq = zeros(2*N + 2, 1);

for t = 1:N
    % Wv + Wgrid + Wdis = Wload + Wch + Wcut
    Aeq(t, [idxGrid(t), idxCh(t), idxDis(t), idxCut(t)]) = [1, -1, 1, -1];
    beq(t) = Wload(t) - Wv(t);

    % E(t+1) = E(t) + eta*Wch(t) - Wdis(t)/eta
    row = N + t;
    Aeq(row, [idxE(t), idxE(t+1), idxCh(t), idxDis(t)]) = ...
        [-1, 1, -eta, 1/eta];
end

Aeq(2*N + 1, idxE(1)) = 1;
beq(2*N + 1) = E0;

% 固定24:00的电量，防止模型靠日末放空电池降低费用
Aeq(2*N + 2, idxE(end)) = 1;
beq(2*N + 2) = E0;

lb = zeros(nVar, 1);
ub = inf(nVar, 1);
ub(idxCh) = Wmax;
ub(idxDis) = Wmax;
lb(idxE) = Emin;
ub(idxE) = Emax;

%% 求解
options = optimoptions('linprog', ...
    'Algorithm', 'dual-simplex-highs', ...
    'Display', 'iter');

[x, totalCost, exitflag] = linprog(f, [], [], Aeq, beq, lb, ub, options);

if exitflag <= 0
    error('线性规划未得到可行最优解，请检查数据和约束。');
end

Wgrid = x(idxGrid);
Wch = x(idxCh);
Wdis = x(idxDis);
Wcut = x(idxCut);
E = x(idxE);

%% 结果统计与检查
totalGrid = sum(Wgrid);
totalCut = sum(Wcut);
balanceError = Wv + Wgrid + Wdis - Wload - Wch - Wcut;
simultaneousIdx = find(Wch > 1e-6 & Wdis > 1e-6);

fprintf('\n========== 问题1优化结果 ==========\n');
fprintf('全天购电量：%.4f kWh\n', totalGrid);
fprintf('全天购电费：%.4f 元\n', totalCost);
fprintf('全天弃光量：%.4f kWh\n', totalCut);
fprintf('储电量范围：%.4f ~ %.4f kWh\n', min(E), max(E));
fprintf('0:00 / 24:00储电量：%.4f / %.4f kWh\n', E(1), E(end));
fprintf('最大电量平衡误差：%.12g kWh\n', max(abs(balanceError)));
fprintf('同时充放电时段数：%d\n', numel(simultaneousIdx));

if isempty(simultaneousIdx)
    fprintf('未出现明显同时充放电现象。\n');
else
    fprintf('存在同时充放电时段，需要进一步检查。\n');
end

% 题目表1要求的整点后10分钟购电量
hoursSelect = [10, 12, 14, 16, 18, 20];
idxSelect = hoursSelect*6 + 1;

fprintf('\n表1  指定时段计划购电量\n');
for i = 1:numel(hoursSelect)
    fprintf('%02d:00-%02d:10：%.4f kWh\n', ...
        hoursSelect(i), hoursSelect(i), Wgrid(idxSelect(i)));
end

% 每4小时汇总一次充放电量
charge4h = zeros(6, 1);
discharge4h = zeros(6, 1);

fprintf('\n表2  储能充放电量\n');
for k = 1:6
    periodIdx = (k-1)*24 + (1:24);
    charge4h(k) = sum(Wch(periodIdx));
    discharge4h(k) = sum(Wdis(periodIdx));

    fprintf('%02d:00-%02d:00：充电 %.4f kWh，放电 %.4f kWh\n', ...
        (k-1)*4, k*4, charge4h(k), discharge4h(k));
end

%% 绘图
timeH = (0:N-1)'*dt;
timeE = (0:N)'*dt;

figure;
plot(timeH, Wgrid, 'LineWidth', 1.5);
xlabel('时间 / h');
ylabel('购电量 / kWh');
title('全天计划购电量');
xlim([0, 24]);
grid on;

figure;
plot(timeH, Wch, 'LineWidth', 1.5);
hold on;
plot(timeH, Wdis, 'LineWidth', 1.5);
xlabel('时间 / h');
ylabel('电量 / kWh');
legend('充电量 Wch', '放电量 Wdis', 'Location', 'best');
title('储能充放电策略');
xlim([0, 24]);
grid on;

figure;
plot(timeE, E, 'LineWidth', 1.5);
xlabel('时间 / h');
ylabel('储电量 / kWh');
title('储能设备电量变化');
xlim([0, 24]);
grid on;

figure;
plot(timeH, Wcut, 'LineWidth', 1.5);
xlabel('时间 / h');
ylabel('弃光量 / kWh');
title('光伏弃光量');
xlim([0, 24]);
grid on;

%% 写入结果文件
% 官方模板第一行从0:10开始，写回前把模型首行移到最后
WgridOutput = [Wgrid(2:end); Wgrid(1)];
outputFile = fullfile(rootDir, 'result1.xlsx');

writematrix(WgridOutput, outputFile, ...
    'Sheet', '计划购电量', 'Range', 'B2');
writematrix(charge4h, outputFile, ...
    'Sheet', '充放电量', 'Range', 'B2');
writematrix(discharge4h, outputFile, ...
    'Sheet', '充放电量', 'Range', 'C2');
writematrix(E(1), outputFile, ...
    'Sheet', '充放电量', 'Range', 'E2');
writematrix(E(end), outputFile, ...
    'Sheet', '充放电量', 'Range', 'E3');

fprintf('\nresult1.xlsx 已写入：%s\n', outputFile);
fprintf('写入计划购电量数量：%d\n', numel(WgridOutput));

% 保存论文绘图数据，后续画组合图时直接读取该表
baselineGrid = max(Wload - Wv, 0);
plotData = table(timeH, price, Wload, Wv, baselineGrid, Wgrid, Wch, ...
    Wdis, Wcut, E(1:N), E(2:N+1), ...
    'VariableNames', {'time_h', 'price', 'load_energy', 'pv_energy', ...
    'baseline_grid', 'grid_energy', 'charge_energy', 'discharge_energy', ...
    'cut_energy', 'storage_start', 'storage_end'});

plotFile = fullfile(supportDir, 'Q1_plot_data.xlsx');
writetable(plotData, plotFile);
fprintf('论文绘图数据已保存：%s\n', plotFile);

% 最后再核对一次循环移位关系
fprintf('\n时间轴检查：Wgrid(1)对应0:00-0:10，Wgrid(61)对应10:00-10:10。\n');
fprintf('结果表首行写入Wgrid(2)，末行写入Wgrid(1)。\n');