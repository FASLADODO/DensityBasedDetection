function [time,boxes,oriIm]=denDectectByFrame(i,pDetectFrame)
v2struct(pDetectFrame);
oriIm=loadImage(testFiles{i},imageType);

im=oriIm.*repmat(roi,1,1,3);
time=tic;
pesClust=pedestrianCluster(testFiles{i},pDen);
%         e1=toc(e);
%         disp(e1);
if dClust
    clf;imshow(im); hold on; vl_plotpoint(pesClust,'.r','MarkerSize',20);
    print(fullfile('temp',['meanshift' num2str(i) '.png']),'-dpng');
end
time=toc(time);

if dBB
    %             clf;imshow(im);
    %             if ~isempty(center),hold on;vl_plotpoint(center);end;
    %             print(fullfile('temp',['clust' num2str(i) '.png']),'-dpng');
    clf;imshow(im);
    hs=bbApply('draw',boxes,'g',1);
    print(fullfile('temp','density',['box' num2str(i) '.png']),'-dpng');
    %             waitforbuttonpress;
end
end
function boxes=denDetect(img,pesClust,SVMModel,BETA,pDetect)
v2struct(pDetect);
w=W/cellSize;h=H/cellSize;
[m1,n1,~]=size(img);
pad=floor(m1/16);im1=imPad(img,pad,'replicate');
pesClust=pesClust+pad;
nScale=numel(scaleRange);
range=-1:1;
boxes={};
bPad=16;
hogIms=cell(1,nScale);
for i=1:nScale
    s=scaleRange(i);
    imS=imResample(im1,s);
    hogIms{i}=computeHog(imS,hogType);
end
for i=1:nScale
    s=scaleRange(i);
    hogIm=hogIms{i};
    boxes1={};
    pesClust1=pesClust*s;
    
    cenCandidate={};
    cenPls={};
    boxes2={};
    for j=1:size(pesClust1,2)
        cenPes=pesClust1(:,j);
        [x,y]=newPlsPos(hogIm,SVMModel,BETA,cenPes(1),cenPes(2),w,h,cellSize,threshold);
        if isempty(x),continue;end;
        
        ftr=getFtrHog(hogIm,x,y,w,h,cellSize);
        if isempty(ftr),continue;end;
        t=calcSVMScore(ftr,SVMModel,'linear');
        if t>fineThreshold,
            boxes1{end+1}=[x-W/2+bPad,y-H/2+bPad,W-2*bPad,H-2*bPad,t,i];
            boxes2{end+1}=[cenPes(1)-W/2+bPad,cenPes(2)-H/2+bPad,W-2*bPad,H-2*bPad,t,i];
            cenCandidate{end+1}=cenPes;
            cenPls{end+1}=[x;y];
        end
    end
    
    if ~isempty(boxes1)
        boxes1=cat(1,boxes1{:});
        boxes1(:,1:4)=boxes1(:,1:4)/s;
        boxes1=removeOutOfRangeBox(boxes1,pad,m1,n1);
        boxes1=bbNms(boxes1,'thr',fineThreshold);
        
        
        boxes2=cat(1,boxes2{:});
        boxes2(:,1:4)=boxes2(:,1:4)/s;
        boxes2=removeOutOfRangeBox(boxes2,pad,m1,n1);
        boxes2=bbNms(boxes2,'thr',fineThreshold);
        if dCenPls
            cenCandidate=cat(2,cenCandidate{:})/s-pad;
            cenPls=cat(2,cenPls{:})/s-pad;
            
            clf;imshow(img);
            hold on;vl_plotpoint(cenCandidate,'.b');
            hold on;vl_plotpoint(cenPls,'.r');
            bbApply('draw',boxes2(:,1:4),'b',1);
            bbApply('draw',boxes1(:,1:4),'r',1);
            print(fullfile('temp',['cenPls' num2str(i) '_' num2str(s) '.png']),'-dpng');
        end
        if dCenBox
            clf;imshow(img);
            bbApply('draw',boxes1,'g',1,'--');
            print(fullfile('temp',['box' num2str(i) '_' num2str(s) '.png']),'-dpng');
        end
        if ~isempty(boxes1),boxes{end+1}=boxes1;end;
    end
end
boxes=cat(1,boxes{:});
boxes=bbNms(boxes);
boxes=bbNms(boxes,'ovrDnm','min');

range=-1:1;
boxes1={};
for i=1:size(boxes,1)
    bb=boxes(i,:);
    sInd=bb(6);
    s=scaleRange(sInd);
    x=bb(1)+bb(3)/2;y=bb(2)+bb(4)/2;
    cenPes=([x;y]+pad)*s;
    [score,centerDense]=denseSearch(hogIms{sInd},cenPes,w,h,SVMModel,cellSize,range);
    boxes2={};
    for k=1:size(centerDense,2)
        x=centerDense(1,k); y=centerDense(2,k);
        boxes1{end+1}=[x-W/2+bPad,y-H/2+bPad,W-2*bPad,H-2*bPad,score(k),s];
    end
end
boxes1=cat(1,boxes1{:});
for i=1:size(boxes1,1)
    s=boxes1(i,6);
    boxes1(i,1:4)=boxes1(i,1:4)/s;
end
boxes1=removeOutOfRangeBox(boxes1,pad,m1,n1);

boxes1=bbNms(boxes1);
boxes1=bbNms(boxes1,'ovrDnm','min');
boxes=boxes1(:,1:5);
end
%%
function [x1,y1]=newPlsPos(hogIm,SVMModel,BETA,x,y,w,h,cellSize,threshold)
x1=[];y1=[];
ftr=getFtrHog(hogIm,x,y,w,h,cellSize);
if isempty(ftr),return;end;
score=calcSVMScore(ftr,SVMModel,'linear');
if score<threshold,return;end;
offset=[1 ftr(:)']*BETA;
x1=x+offset(1);y1=y+offset(2);
end
%%
function centers=pedestrianCluster(fnm,pDen)
img=getIm(fnm,pDen);
den=mallden(img,pDen);
if pDen.colorDen
    colormap('jet');
    clf;imagesc(den);
    print(fullfile('temp','denImage.png'),'-dpng');
end
% den=imfilter(den,fspecial('gaussian',[5 5],3));
t=max(den(:))*0.0001;
den(den<t)=0;
den(den>=t)=1;

if pDen.dDenIm
    clf;imshow(den);
    print(fullfile('temp','denIm.png'),'-dpng');
end

den=medfilt2(den,[3 3]);
[r,c]=find(den);
x=[c r]';

if pDen.dDenFilt
    clf;imshow(den);
    %     hold on;vl_plotpoint(x);
    print(fullfile('temp','denImfilt.png'),'-dpng');
end
bandwidth=pDen.bandwidth;
[centers,~,~] = MeanShiftCluster(x,bandwidth);
centers=centers*pDen.spacing;
end
%%
function testpedestrianCluster
[~,fnm,~]=fileparts(testFiles{i});
%     imwrite(loadImage(testFiles{i},'rgb'),fullfile('temp',[fnm '.png']));
imwrite(mat2gray(den),fullfile('temp',[fnm '_den.png']));
clf;
imshow(loadImage(testFiles{i},'rgb'));
hold on;
vl_plotpoint(clustCent*pDen.spacing);
print(fullfile('temp',[fnm 'clust.png']),'-dpng');
end