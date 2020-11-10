function varargout = match_S20(Initial,ConfigName,Nbunch,SextupoleMatch)
%MATCHS20 Configure Sector 20 magnets by matching in-memory Lucretia file
% First load Lucretia file from facet2-lattice/Lucretia/models repository directory.
% Available configurations depicted in presentation files on:
% https://www.slac.stanford.edu/~whitegr/F2_S2E
%
% Use DeckTool to convert to new XSIF or BMAD lattices
%
% (Matlab optimization toolbox required)
%
%opts=match_S20('GetOps')
% Lists available matching configuration options
%
%match_S20(Initial,ConfigurationName,Nbunch)
%
% Initial : Lucretia Initial structire from loaded repository model
%
% ConfigurationName :
% "PWFA_15cm" - PWFA oven IP (PENT), beta*_x,y = 15cm
% "PWFA_50cm" - PWFA oven IP (PENT), beta*_x,y = 50cm
% "PWFA_100cm" - PWFA oven IP (PENT), beta*_x,y = 100cm
% "SFQED" - Optics optimized for SFQED experiment, beta* = 10m, E=13 GeV
% "Filamentation_Gas" - Optimized for Filamentation gas target experiment
%
% Nbunch = 1 or 2
%  If 2, then optimize for second ("witness") bunch in 2-bunch configuration (with energy determined from tracking studies)
%
%match_s20(Initial,ConfigurationName,Nbunch,true)
%
% Also match sextupoles in Sectro 20 chicane to minimize chromatic abberations at the IP
global BEAMLINE PS

varargout={};
if isequal(Initial,'GetOpts') % return considered Sector 20 match optionss
  varargout{1} = ["pwfa_15cm" "pwfa_50cm" "pwfa_100cm" "sfqed" "filamentation_gas"];
  return
end

if nargin<3
  error('Check input arguments');
end

% Assumed PS not assigned in base lattice
if ~isempty(PS)
  error('PS not empty')
end

if ~exist('SextupoleMatch','var')
  SextupoleMatch=false;
end

odisp='iter';
% odisp='off';

ipname='PENT';
E0=[];
if Nbunch==2
  E0=9.921; % Witness bunch energy
end
de=0.2e-2; % rms energy spread in S20
psno=1:5;
ConfigName = lower(string(ConfigName)) ;
switch ConfigName
  case "pwfa_15cm"
    ipbeta=[0.15 0.15];
  case "pwfa_50cm"
    ipbeta=[0.5 0.5];
  case "pwfa_100cm"
    ipbeta=[1 1];
  case "tcav"
    ipbeta=[0.05 0.05];
    ipname='DWIN';
  case "sfqed"
    psno=1:5;
    ipbeta=[10 10];
    E0=13;
    de=0.1e-2;
  case "kraken_roundbeam"
    ipname='KRK';
    ipbeta=[0.29 0.29];
    psno=3:5;
  case "kraken_flatbeam"
    ipname='KRK';
    ipbeta=[2 0.2];
    psno=3:5;
  case "filamentation_solid"
    ipbeta=[0.15 0.15];
  case "filamentation_gas"
    ipbeta=[0.7 0.7];
  otherwise
    error('Unknown configuration');
end

% Required beamline indices
iscr=findcells(BEAMLINE,'Name','PHOSPHOR');
i1=findcells(BEAMLINE,'Name','BEGBC20');
l3_1=findcells(BEAMLINE,'Name','BEGL3F_1');
% l3_2=findcells(BEAMLINE,'Name','ENDL3F_1');
ipele=findcells(BEAMLINE,'Name',ipname);

% Set specific design energy if requested
if ~isempty(E0)
  SetDesignMomentumProfile(l3_1,length(BEAMLINE),Initial.Q,BEAMLINE{l3_1}.P,E0);
end

% Get Initial structure at start of S20
[~,T]=GetTwiss(1,i1,Initial.x.Twiss,Initial.y.Twiss);
I=TwissToInitial(T,i1,Initial);
I.Q=2e-9;
I.x.NEmit=3.0e-6; I.y.NEmit=3e-6;
I.SigPUncorrel=I.Momentum.*de;

% Form power supplies for matching magnet strengths
qm={'QFF1*' 'QFF2*' 'QFF4*' 'QFF5*' 'QFF6*'};
for iquad=1:5
  iele=findcells(BEAMLINE,'Name',qm{iquad});
  AssignToPS( iele, length(PS)+1 ) ;
end
MovePhysicsVarsToPS(1:length(PS));

if ConfigName=="sfqed"
  for ips=1:length(PS)
    PS(ips).Ampl=0; PS(ips).SetPt=0;
  end
end

% Match IP
lval=[-20.3 -21.3 -24.6 -75.8 -44.1]; uval=[20.3 21.3 24.6 75.8 44.1];
optim='lsqnonlin';
M=Match;
for ips=psno
  M.addVariable('PS',ips,'Ampl',lval(ips),uval(ips)); 
end
M.beam=MakeBeam6DGauss(I,1e3,3,1);
M.iInitial=i1;
M.initStruc=I;
M.verbose=false; % see optimizer output or not
M.optim=optim;
M.optimDisplay=odisp;
M.addMatch(ipele,'alpha_x',0,0.0001);
M.addMatch(ipele,'alpha_y',0,0.0001);
M.addMatch(ipele,'beta_x',ipbeta(1),0.0001);
M.addMatch(ipele,'beta_y',ipbeta(2),0.0001);
M.doMatch();
if strcmp(odisp,'iter')
  disp(M);
end

% Match dump optics from IP
if ~startsWith(ConfigName,"kraken")
  qd=findcells(BEAMLINE,'Name','QS1');
  qf=findcells(BEAMLINE,'Name','QS2');
  for iele=qf;BEAMLINE{iele}.B=1; end
  for iele=qd;BEAMLINE{iele}.B=-1; end
  AssignToPS(qf,length(PS)+1); psqf=length(PS);
  AssignToPS(qd,length(PS)+1); psqd=length(PS);
  MovePhysicsVarsToPS(psqf);
  MovePhysicsVarsToPS(psqd);
  qmax=100;
  M=Match;
  M.beam=MakeBeam6DGauss(I,1e3,3,1);
  M.iInitial=i1;
  M.initStruc=I;
  M.verbose=false; % see optimizer output or not
  M.optim='fminsearch';
  M.optimDisplay=odisp;
  if ConfigName == "sfqed"
    M.addMatch(iscr,'R',0,1e-14,'11');
    M.addMatch(iscr,'R',0,1e-14,'33');
    M.addMatch(iscr,'beta_y',0,ipbeta(2));
  else
    M.addMatch(iscr,'R',0,1e-9,'12');
    M.addMatch(iscr,'R',0,1e-9,'34');
  end
  M.addVariable('PS', psqf,'Ampl',0,qmax*2);
  M.addVariable('PS', psqd,'Ampl',-qmax*2,0);
  M.doMatch();
  if strcmp(odisp,'iter')
    disp(M);
  end
end

% Match sextupoles
if SextupoleMatch
  disp('Optimizing Sextupole Strengths...');
  AssignToPS(findcells(BEAMLINE,'Name','S1E*'),length(PS)+1); sps(1)=length(PS); MovePhysicsVarsToPS(sps(1));
  AssignToPS(findcells(BEAMLINE,'Name','S2E*'),length(PS)+1); sps(2)=length(PS); MovePhysicsVarsToPS(sps(2));
  for ips=sps
    PS(ips).Ampl=0; PS(ips).SetPt=0;
  end
  SetTrackFlags('ZMotion',1,1,length(BEAMLINE));
  if ConfigName == "sfqed"
    tind=iscr;
  else
    tind=ipele;
  end
  M=Match;
  M.beam=MakeBeam6DGauss(I,1e4,3,1);
  M.iInitial=i1;
  M.initStruc=I;
  M.verbose=false; % see optimizer output or not
  M.optim='lsqnonlin';
  M.optimDisplay='iter';
  M.addVariable('PS', sps(1),'Ampl',-2170.6,2170.6); % S1's
  M.addVariable('PS', sps(2),'Ampl',-776.8,776.8); % S2's
  M.addMatch(tind,'NEmit_x',0,I.x.NEmit);
  M.doMatch();
  disp(M);
end

% Display matched magnet values and restore database to BEAMLINE
qm=[qm {'QS1' 'QS2'}];
for ips=1:length(PS)
  for iele=PS(ips).Element
    if GetTrueStrength(iele)==0
      BEAMLINE{iele}.B=0;
    else
      RenormalizePS(ips);
    end
    BEAMLINE{iele}.PS=0;
  end
end
PS=[];
TwissPlot(i1,length(BEAMLINE),I,[1 1 1]);
clight=2.99792458e8; % speed of light (m/sec)
Cb=1e9/clight;       % rigidity conversion (T-m/GeV)
for ips=1:length(qm)
  iele=findcells(BEAMLINE,'Name',qm{ips});
  fprintf('K%s := %g\n',BEAMLINE{iele(1)}.Name,BEAMLINE{iele(1)}.B/(BEAMLINE{iele(1)}.L*Cb*BEAMLINE{iele(1)}.P));
end
bmax=[uval.*10 440 440];
for ips=1:length(qm)
  iele=findcells(BEAMLINE,'Name',qm{ips});
  fprintf('BDES %s := %.1f (BMAX = %.1f) \n',BEAMLINE{iele(1)}.Name,10*sum(arrayfun(@(x) BEAMLINE{x}.B,iele)),bmax(ips));
end
if SextupoleMatch
  snames={'S1E','S2E'};
  for isext=1:length(snames)
    iele=findcells(BEAMLINE,'Name',sprintf('%s*',snames{isext}));
    fprintf('K%s := %g\n',BEAMLINE{iele(1)}.Name,BEAMLINE{iele(1)}.B/(BEAMLINE{iele(1)}.L*Cb*BEAMLINE{iele(1)}.P));
  end
end