function SEMMarkerTracker
% Developed by Shaolou Wei, SC.D. and Dr.-Ing Xinren Chen, at MPI-SusMat
% Critical discussion with PD Dr.-Ing Stefan Zaefferer
% SEMMarkerTracker - semi-automatic fiducial tracking in ordered SEM images.
% MATLAB R2019b+ recommended. Image Processing Toolbox required for
% normxcorr2; no Computer Vision Toolbox required.
% Run: SEMMarkerTracker
% Coordinates are MATLAB image coordinates: x right, y DOWN, in pixels.

S = struct('files',{{}},'imgs',{{}},'xy',[],'status',{{}},'scores',[], ...
    'frame',1,'diameter',12,'searchRadius',22,'templateRadius',12, ...
    'selected',0,'mode','select','accepted',false(1,0),'dirty',false, ...
    'path','','showLabels',true,'lastMessage','');
% Keep an explicit handle to the strain window so it can always be reopened.
strainFig=[];
F = figure('Name','SEM fiducial marker tracker','NumberTitle','off', ...
    'Color',[.14 .16 .19],'MenuBar','none','ToolBar','figure', ...
    'Units','normalized','Position',[.07 .08 .86 .82], ...
    'CloseRequestFcn',@onClose,'KeyPressFcn',@onKey,'DefaultTextFontName','Arial', ...
    'DefaultAxesFontName','Arial','DefaultUicontrolFontName','Arial', ...
    'DefaultUipanelFontName','Arial');
A = axes('Parent',F,'Units','normalized','Position',[.04 .09 .72 .80]);
set(A,'Color',[.06 .07 .08]);
P = uipanel(F,'Title','Tracking controls','Units','normalized', ...
    'Position',[.79 .04 .20 .85],'BackgroundColor',[.19 .21 .24], ...
    'ForegroundColor','w','FontName','Arial','FontSize',13,'FontWeight','bold');

% More generous button spacing and enlarged parameter labels, while
% reserving an information area at the bottom of the control panel.

y=.97; h=.032; gap=.007;
addBtn('Import ordered TIFF',@importImages);
addBtn('Open saved session',@loadSession);
addBtn('Save session (.mat)',@saveSession);
addBtn('Export coordinates (.csv)',@exportCSV);
addBtn('Strain analysis / maps',@openStrain);

y=y-.012;
addLabel('Dot diameter (pixels)'); Ediam=addEdit('12',@setDiameter);
addLabel('Search radius (pixels)'); Esearch=addEdit('22',@setSearch);
addLabel('Template radius (pixels)'); Etemp=addEdit('12',@setTemplate);

y=y-.008;
addBtn('Add dots (click centers)',@modeAdd);
addBtn('Move selected dot (click)',@modeMove);
addBtn('Select dot (click nearby)',@modeSelect);
addBtn('Mark selected missing',@markMissing);
addBtn('Restore selected (click)',@modeRestore);
addBtn('Delete selected ID (all frames)',@deleteMarker);

y=y-.008;
addBtn('Auto-track CURRENT frame',@trackCurrent);
addBtn('Review unmatched IDs',@reviewUnmatched);
addBtn('Accept frame / Next >',@acceptNext);
addBtn('< Previous frame',@previousFrame);
addBtn('Jump to frame...',@jumpFrame);

y=y-.01;
Cshow=uicontrol(P,'Style','checkbox','String','Show marker IDs', ...
    'Units','normalized','Position',[.04 y .90 h], ...
    'BackgroundColor',[.19 .21 .24],'ForegroundColor','w', ...
    'Value',1,'Callback',@toggleLabels,'FontName','Arial','FontSize',10);

y=y-h-gap;
Info=uicontrol(P,'Style','text','String','Import images to begin.', ...
    'Units','normalized','Position',[.03 .018 .94 max(.045,y-.040)], ...
    'BackgroundColor',[.19 .21 .24],'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontSize',10,'FontName','Arial');
uicontrol(F,'Style','text','String','SEM fiducial marker tracker (V1.0 by Shaolou Wei, Sc.D. and Dr.-Ing Xinren Chen, MPI-SusMat)', ...
    'Units','normalized','Position',[.04 .935 .72 .045], ...
    'BackgroundColor',[.14 .16 .19],'ForegroundColor','w', ...
    'FontName','Arial','FontWeight','bold','FontSize',13,'HorizontalAlignment','center');
set(A,'ButtonDownFcn',@imageClick);
uicontrol(F,'Style','text','String', ...
    'Please contact sl.wei@mpie.de or x.chen@mpie.de if you notice any bug!', ...
    'Units','normalized','Position',[.04 .013 .72 .038], ...
    'BackgroundColor',[.14 .16 .19],'ForegroundColor','w', ...
    'FontName','Arial','FontWeight','normal','FontSize',12, ...
    'HorizontalAlignment','center');

    function addBtn(label,callback)
        uicontrol(P,'Style','pushbutton','String',label,'Units','normalized', ...
            'Position',[.04 y .92 h], 'Callback',callback,'FontSize',10,'FontName','Arial');
        y=y-h-gap;
    end
    function addLabel(label)
        uicontrol(P,'Style','text','String',label,'Units','normalized', ...
            'Position',[.04 y .92 .026],'BackgroundColor',[.19 .21 .24], ...
            'ForegroundColor','w','HorizontalAlignment','left','FontSize',12,'FontName','Arial');
        y=y-.026;
    end
    function e=addEdit(value,callback)
        e=uicontrol(P,'Style','edit','String',value,'Units','normalized', ...
            'Position',[.04 y .92 .031],'Callback',callback, ...
            'FontName','Arial','FontSize',10);
        y=y-.031-gap;
    end
    function setDiameter(~,~)
        S.diameter=positiveNumber(Ediam,S.diameter);
        S.templateRadius=max(5,round(S.diameter));
        set(Etemp,'String',num2str(S.templateRadius)); draw();
    end
    function setSearch(~,~), S.searchRadius=positiveNumber(Esearch,S.searchRadius); end
    function setTemplate(~,~), S.templateRadius=positiveNumber(Etemp,S.templateRadius); end
    function v=positiveNumber(e,old)
        v=str2double(get(e,'String'));
        if ~isfinite(v)||v<2, v=old; end
        v=round(v); set(e,'String',num2str(v));
    end
    function importImages(~,~)
        [names,folder]=uigetfile({'*.tif;*.tiff;*.png;*.jpg','SEM images'}, ...
            'Select ALL images in milling order','MultiSelect','on');
        if isequal(names,0),return;end
        if ischar(names),names={names};end
        names=sortNaturally(names);
        imgs=cell(1,numel(names));
        for k=1:numel(names)
            im=imread(fullfile(folder,names{k}));
            if ndims(im)==3,im=rgb2gray(im);end
            imgs{k}=im2double(im);
            if k>1 && ~isequal(size(imgs{k}),size(imgs{1}))
                errordlg('All frames must have identical pixel dimensions.');return;
            end
        end
        S.files=cellfun(@(s)fullfile(folder,s),names,'UniformOutput',false);
        S.imgs=imgs; S.frame=1; S.xy=nan(0,2,numel(imgs));
        S.scores=nan(0,numel(imgs));S.status=cell(0,numel(imgs));
        S.accepted=false(1,numel(imgs)); S.mode='add';S.selected=0;
        S.path=fullfile(folder,'SEMMarkerTrackingSession.mat');S.dirty=true;
        draw(); msg(sprintf('Loaded %d frames. Click dot centers in frame 1.\nFiles sorted by trailing frame number; verify order.',numel(imgs)));
    end
    function names=sortNaturally(names)
        nums=nan(numel(names),1);
        for k=1:numel(names)
            [~,base]=fileparts(names{k}); tok=regexp(base,'\d+','match');
            if ~isempty(tok),nums(k)=str2double(tok{end});end
        end
        if all(isfinite(nums)) && numel(unique(nums))==numel(nums)
            [~,idx]=sort(nums);names=names(idx);
        else
            names=sort(names);
            warndlg('Filenames do not have unique trailing numbers; verify imported order.');
        end
    end
    function modeAdd(~,~)
        if S.frame~=1,msg('New marker IDs can only be added on reference frame 1.');return;end
        S.mode='add';draw();
    end
    function modeMove(~,~),S.mode='move';draw();end
    function modeSelect(~,~),S.mode='select';draw();end
    function modeRestore(~,~),S.mode='restore';draw();end
    function toggleLabels(~,~),S.showLabels=logical(get(Cshow,'Value'));draw();end
    function imageClick(~,~)
        if isempty(S.imgs),return;end
        p=get(A,'CurrentPoint');q=p(1,1:2);
        sz=size(S.imgs{S.frame});
        if any(q<1)||q(1)>sz(2)||q(2)>sz(1),return;end
        switch S.mode
            case 'add'
                if S.frame~=1,return;end
                S.xy(end+1,1:2,1:numel(S.imgs))=nan;
                S.scores(end+1,1:numel(S.imgs))=nan;
                S.status(end+1,1:numel(S.imgs))={'untracked'};
                S.selected=size(S.xy,1);
                S.xy(S.selected,:,1)=refineCentroid(S.imgs{1},q,S.diameter);
                S.status{S.selected,1}='manual';
            case 'select'
                S.selected=nearest(q);
            case {'move','restore'}
                if S.selected<1,msg('Select a marker first.');return;end
                S.xy(S.selected,:,S.frame)=refineCentroid(S.imgs{S.frame},q,S.diameter);
                S.status{S.selected,S.frame}='manual';
                S.scores(S.selected,S.frame)=nan;
                S.mode='select';
        end
        S.dirty=true;draw();
    end
    function id=nearest(q)
        id=0;if isempty(S.xy),return;end
        p=S.xy(:,:,S.frame);ok=all(isfinite(p),2);
        if ~any(ok),return;end
        d=hypot(p(:,1)-q(1),p(:,2)-q(2));d(~ok)=inf;
        [val,idx]=min(d);if val<max(15,2*S.diameter),id=idx;end
    end
    function q=refineCentroid(im,q,diam)
        % Intensity-weighted centroid in a small window, with background removal.
        r=max(3,round(diam*.65)); [H,W]=size(im);
        xa=max(1,floor(q(1))-r);xb=min(W,ceil(q(1))+r);
        ya=max(1,floor(q(2))-r);yb=min(H,ceil(q(2))+r);
        z=im(ya:yb,xa:xb); bg=prctile(z(:),25);
        w=max(z-bg,0).^2;[xx,yy]=meshgrid(xa:xb,ya:yb);
        if sum(w(:))>eps,q=[sum(xx(:).*w(:))/sum(w(:)),sum(yy(:).*w(:))/sum(w(:))];end
    end
    function markMissing(~,~)
        if S.selected<1||isempty(S.imgs),return;end
        if S.frame==1,msg('Reference marker cannot be missing; delete the ID instead.');return;end
        S.xy(S.selected,:,S.frame)=nan;
        S.status{S.selected,S.frame}='missing';S.scores(S.selected,S.frame)=nan;
        % Invalidate subsequent automatic estimates until manually restored.
        for future=S.frame+1:numel(S.imgs)
            if strcmp(S.status{S.selected,future},'manual'),break;end
            S.xy(S.selected,:,future)=nan;
            S.status{S.selected,future}='missing';
            S.scores(S.selected,future)=nan;
        end
        S.dirty=true;draw();
    end
    function deleteMarker(~,~)
        if S.selected<1,return;end
        answ=questdlg(sprintf('Delete marker ID %d from ALL frames?',S.selected), ...
            'Confirm delete','Delete','Cancel','Cancel');
        if ~strcmp(answ,'Delete'),return;end
        S.xy(S.selected,:,:)=[];S.status(S.selected,:)=[];
        S.scores(S.selected,:)=[];S.selected=0;S.dirty=true;draw();
    end
    function trackCurrent(~,~)
        if isempty(S.imgs)||S.frame==1,return;end
        n=S.frame;prev=n-1;N=size(S.xy,1);
        if N==0,msg('Initialize dots in frame 1 first.');return;end
        I0=S.imgs{prev};I1=S.imgs{n};
        % Robust global translation from phase correlation, only for prediction.
        drift=phaseTranslation(I0,I1);
        % Prior per-marker velocity, if available; otherwise use image drift.
        proposed=nan(N,2);quality=nan(N,1);
        for i=1:N
            if strcmp(S.status{i,n},'manual')||strcmp(S.status{i,n},'missing'),continue;end
            % Use the last known valid location, even after a missed frame.
            % Never use coordinates from future frames when revisiting a step.
            last=find(all(isfinite(reshape(S.xy(i,:,1:n-1),2,[])),1),1,'last');
            if isempty(last)||last>=n,continue;end
            p=reshape(S.xy(i,:,last),1,2);
            pred=p+drift*(n-last);
            if last>=2
                before=find(all(isfinite(reshape(S.xy(i,:,1:last-1),2,[])),1),1,'last');
                if ~isempty(before)
                    old=reshape(S.xy(i,:,before),1,2);
                    velocity=(p-old)/(last-before);
                    if norm(velocity-drift)<S.searchRadius/2
                        pred=p+velocity*(n-last);
                    end
                end
            end
            [pt,score]=matchPatch(S.imgs{last},I1,p,pred,S.templateRadius,S.searchRadius);
            if score>=.60 && norm(pt-pred)<=S.searchRadius+1
                proposed(i,:)=pt;quality(i)=score;
            end
        end
        % Reject near-duplicate assignments: two IDs must not occupy one dot.
        for i=1:N
            if ~all(isfinite(proposed(i,:))),continue;end
            for j=i+1:N
                if all(isfinite(proposed(j,:))) && norm(proposed(i,:)-proposed(j,:))<max(3,S.diameter*.45)
                    if quality(i)>=quality(j),proposed(j,:)=nan;quality(j)=nan;
                    else,proposed(i,:)=nan;quality(i)=nan;end
                end
            end
        end
        for i=1:N
            if strcmp(S.status{i,n},'manual')||strcmp(S.status{i,n},'missing'),continue;end
            S.xy(i,:,n)=proposed(i,:);S.scores(i,n)=quality(i);
            if all(isfinite(proposed(i,:))),S.status{i,n}='auto';
            else,S.status{i,n}='untracked';end
        end
        S.dirty=true;draw();
        msg(sprintf('Frame %d: %d/%d automatically tracked. Drift prediction [%.2f, %.2f] px.', ...
            n-1,sum(all(isfinite(S.xy(:,:,n)),2)),N,drift(1),drift(2)));
        reviewUnmatched();
    end
    function reviewUnmatched(~,~)
        % Interactive, ID-by-ID recovery. Never infer a coordinate for a
        % failed match. The user either clicks the visible dot, explicitly
        % abandons it for THIS frame, or postpones the remaining review.
        if isempty(S.imgs)||S.frame==1||isempty(S.xy),return;end
        n=S.frame;
        bad=find(~all(isfinite(S.xy(:,:,n)),2));
        if isempty(bad),msg('No unmatched marker IDs in this frame.');return;end
        for kk=1:numel(bad)
            id=bad(kk);
            if all(isfinite(S.xy(id,:,n))),continue;end
            earlier=find(all(isfinite(reshape(S.xy(id,:,1:n-1),2,[])),1),1,'last');
            if isempty(earlier),continue;end
            previous=reshape(S.xy(id,:,earlier),1,2);
            reference=reshape(S.xy(id,:,1),1,2);
            result=reviewOneMarker(id,previous,reference,earlier);
            if strcmp(result,'later'),break;end
        end
        S.mode='select';S.dirty=true;draw();
        left=sum(~all(isfinite(S.xy(:,:,n)),2));
        msg(sprintf('Frame %02d review finished: %d IDs without coordinates. Reopen Review unmatched IDs to revisit.',n-1,left));
    end
    function result=reviewOneMarker(id,previous,reference,earlier)
        result='later';
        n=S.frame; I=S.imgs{n};[H,W]=size(I);
        R=figure('Name',sprintf('Review marker ID %d - frame %02d',id,n-1), ...
            'NumberTitle','off','Color',[.15 .17 .20], ...
            'Units','normalized','Position',[.22 .15 .56 .72], ...
            'MenuBar','none','ToolBar','figure','WindowStyle','modal', ...
            'CloseRequestFcn',@postpone,'DefaultTextFontName','Arial');
        ax=axes('Parent',R,'Units','normalized','Position',[.07 .19 .86 .72]);
        imagesc(ax,I);colormap(ax,gray(256));axis(ax,'image');
        set(ax,'YDir','reverse');hold(ax,'on');
        % Dashed circles indicate the LAST OBSERVED position, NOT a
        % fabricated location in the current frame.
        theta=linspace(0,2*pi,180);
        rr=S.diameter/2;
        plot(ax,previous(1)+rr*cos(theta),previous(2)+rr*sin(theta), ...
            '--','Color',[1 .85 .12],'LineWidth',2,'HitTest','off');
        plot(ax,previous(1),previous(2),'+','Color',[1 .85 .12], ...
            'MarkerSize',12,'LineWidth',1.5,'HitTest','off');
        text(ax,previous(1)+rr+5,previous(2),sprintf('ID %d (last frame %02d)',id,earlier-1), ...
            'Color','y','FontWeight','bold','FontSize',12, ...
            'BackgroundColor',[.12 .12 .12],'HitTest','off');
        if all(isfinite(reference))
            plot(ax,reference(1),reference(2),'c+','MarkerSize',9, ...
                'LineWidth',1.3,'HitTest','off');
        end
        hold(ax,'off');
        radius=max(110,5*S.searchRadius);
        xlim(ax,[max(.5,previous(1)-radius),min(W+.5,previous(1)+radius)]);
        ylim(ax,[max(.5,previous(2)-radius),min(H+.5,previous(2)+radius)]);
        title(ax,sprintf('Frame %02d | ID %d | yellow dashed: last observed; cyan +: reference',n-1,id), ...
            'Color','w','FontWeight','bold','FontName','Arial');
        set(findobj(ax,'Type','image'),'HitTest','off');
        set(ax,'ButtonDownFcn',@manualClick);
        uicontrol(R,'Style','text','Units','normalized','Position',[.06 .115 .88 .05], ...
            'String','Click the recognizable dot center to restore its ID, or choose Abandon for this frame.', ...
            'ForegroundColor','w','BackgroundColor',[.15 .17 .20], ...
            'FontWeight','bold','FontSize',11,'HorizontalAlignment','center');
        uicontrol(R,'Style','pushbutton','Units','normalized', ...
            'Position',[.17 .035 .29 .055],'String','Abandon this frame', ...
            'Callback',@abandon);
        uicontrol(R,'Style','pushbutton','Units','normalized', ...
            'Position',[.54 .035 .29 .055],'String','Review remaining later', ...
            'Callback',@postpone);
        uiwait(R);
        if isgraphics(R),delete(R);end
        function manualClick(~,~)
            pt=get(ax,'CurrentPoint');q=pt(1,1:2);
            if any(~isfinite(q))||q(1)<1||q(1)>W||q(2)<1||q(2)>H,return;end
            S.xy(id,:,n)=refineCentroid(I,q,S.diameter);
            S.status{id,n}='manual';S.scores(id,n)=nan;
            result='manual';uiresume(R);
        end
        function abandon(~,~)
            S.xy(id,:,n)=nan;S.status{id,n}='missing';
            S.scores(id,n)=nan;result='abandon';uiresume(R);
        end
        function postpone(~,~)
            result='later';uiresume(R);
        end
    end
    function [q,score]=matchPatch(im0,im1,p,pred,r,search)
        q=[nan nan];score=-inf;[H,W]=size(im0);
        cx=round(p(1));cy=round(p(2));
        if cx-r<1||cx+r>W||cy-r<1||cy+r>H,return;end
        patch=im0(cy-r:cy+r,cx-r:cx+r);
        sx=max(1,floor(pred(1)-search-r));ex=min(W,ceil(pred(1)+search+r));
        sy=max(1,floor(pred(2)-search-r));ey=min(H,ceil(pred(2)+search+r));
        searchImg=im1(sy:ey,sx:ex);
        if any(size(searchImg)<size(patch))||std(patch(:))<.002,return;end
        corr=normxcorr2(patch,searchImg);
        [peak,idx]=max(corr(:));[py,px]=ind2sub(size(corr),idx);
        center=[sx+px-size(patch,2)+r,sy+py-size(patch,1)+r];
        if norm(center-pred)>search+1,return;end
        % Quadratic subpixel interpolation around correlation peak.
        off=[0 0];
        if px>1&&px<size(corr,2)
            v=corr(py,px-1:px+1);den=v(1)-2*v(2)+v(3);
            if abs(den)>1e-9,off(1)=max(-.5,min(.5,.5*(v(1)-v(3))/den));end
        end
        if py>1&&py<size(corr,1)
            v=corr(py-1:py+1,px);den=v(1)-2*v(2)+v(3);
            if abs(den)>1e-9,off(2)=max(-.5,min(.5,.5*(v(1)-v(3))/den));end
        end
        q=center+off+(p-[cx cy]);score=peak;
    end
    function d=phaseTranslation(a,b)
        % Phase correlation with mean-subtraction and Hann-like taper.
        [h,w]=size(a); yy=(0:h-1)';xx=0:w-1;
        win=(.5-.5*cos(2*pi*yy/max(1,h-1)))*(.5-.5*cos(2*pi*xx/max(1,w-1)));
        aa=fft2((a-mean(a(:))).*win);bb=fft2((b-mean(b(:))).*win);
        c=bb.*conj(aa);c=c./max(abs(c),1e-12);v=real(ifft2(c));
        [~,id]=max(v(:));[iy,ix]=ind2sub(size(v),id);
        dx=ix-1;dy=iy-1;if dx>w/2,dx=dx-w;end;if dy>h/2,dy=dy-h;end
        d=[dx dy];
        if norm(d)>max(size(a))/4,d=[0 0];end
    end
    function acceptNext(~,~)
        if isempty(S.imgs),return;end
        wasAccepted=S.accepted(S.frame);
        wasFinal=S.frame==numel(S.imgs);
        S.accepted(S.frame)=true;S.dirty=true;
        if ~wasFinal
            S.frame=S.frame+1;S.mode='select';
            if ~any(all(isfinite(S.xy(:,:,S.frame)),2)),trackCurrent();end
        end
        draw();
        % Returning from analysis starts an editing pass. Even if the final
        % frame was accepted previously, clicking Next on that frame must
        % regenerate the analysis from the CURRENT corrected coordinates.
        editingPass=isappdata(F,'SEMReturnFromStrain') && ...
            logical(getappdata(F,'SEMReturnFromStrain'));
        if wasFinal && editingPass
            setappdata(F,'SEMReturnFromStrain',false);
            openStrain();
        elseif wasFinal && ~wasAccepted && all(S.accepted)
            choice=questdlg('All frames accepted. Open strain analysis now?', ...
                'Tracking complete','Analyze now','Later','Analyze now');
            if strcmp(choice,'Analyze now'),openStrain();end
        end
    end
    function previousFrame(~,~)
        if isempty(S.imgs),return;end
        S.frame=max(1,S.frame-1);S.mode='select';draw();
    end
    function jumpFrame(~,~)
        if isempty(S.imgs),return;end
        a=inputdlg(sprintf('Frame number (0 to %d):',numel(S.imgs)-1), ...
            'Jump to frame',1,{num2str(S.frame-1)});
        if isempty(a),return;end
        n=str2double(a{1})+1;
        if isfinite(n)&&n==round(n)&&n>=1&&n<=numel(S.imgs)
            S.frame=n;S.mode='select';draw();
        end
    end
    function onKey(~,evt)
        if isempty(S.imgs),return;end
        switch evt.Key
            case 'rightarrow',acceptNext();
            case 'leftarrow',previousFrame();
            case 'delete',markMissing();
            case 'a',modeAdd();
            case 'm',modeMove();
            case 's',modeSelect();
        end
    end
    function draw()
        cla(A);
        if isempty(S.imgs),return;end
        imagesc(A,S.imgs{S.frame});colormap(A,gray(256));axis(A,'image');
        set(A,'YDir','reverse','XLim',[.5 size(S.imgs{S.frame},2)+.5], ...
            'YLim',[.5 size(S.imgs{S.frame},1)+.5]);hold(A,'on');
        p=S.xy(:,:,S.frame);
        for i=1:size(p,1)
            if ~all(isfinite(p(i,:))),continue;end
            if strcmp(S.status{i,S.frame},'manual'),color=[.2 1 .4];
            else,color=[1 .75 .15];end
            if i==S.selected,color=[1 .2 .25];end
            % Draw marker outlines in IMAGE PIXEL coordinates, not points.
            % Diameter therefore matches the Dot diameter setting exactly
            % regardless of window size, screen DPI, or axes zoom.
            d=S.diameter;
            rectangle('Parent',A,'Position',[p(i,1)-d/2, p(i,2)-d/2, d, d], ...
                'Curvature',[1 1],'EdgeColor',color,'LineWidth',1.3, ...
                'FaceColor','none','HitTest','off');
            if S.showLabels
                text(A,p(i,1)+5,p(i,2)-5,num2str(i),'Color',color, ...
                    'FontName','Arial','FontSize',12,'FontWeight','bold', ...
                    'BackgroundColor',[0.12 0.12 0.12],'Margin',1,'HitTest','off');
            end
        end
        hold(A,'off');
        set(findobj(A,'Type','image'),'HitTest','off');
        title(A,sprintf('Frame %02d/%02d | %s | %d/%d visible | Selected ID %d', ...
            S.frame-1,numel(S.imgs)-1,S.mode, ...
            sum(all(isfinite(p),2)),size(p,1),S.selected), ...
            'Interpreter','none','Color','w','FontName','Arial','FontSize',11);
        set(A,'ButtonDownFcn',@imageClick);
        msg(sprintf('Frame %02d: %s\nMode: %s\nManual=green, auto=yellow, selected=red.\nClick image to act.\nArrow keys: previous / accept+next.\nA=add (frame 00), M=move, S=select.\nUnmatched markers remain NaN.\nVerify every stage before accepting.', ...
            S.frame-1,S.files{S.frame},S.mode));
    end
    function msg(t),set(Info,'String',t);drawnow limitrate;end
    function saveSession(~,~)
        if isempty(S.imgs),return;end
        [f,p]=uiputfile('*.mat','Save tracking session',S.path);
        if isequal(f,0),return;end
        data=S;data.imgs={};data.path=fullfile(p,f);
        save(fullfile(p,f),'data','-v7.3');S.path=fullfile(p,f);S.dirty=false;
        msg(['Session saved: ' S.path]);
    end
    function loadSession(~,~)
        [f,p]=uigetfile('*.mat','Open tracking session');if isequal(f,0),return;end
        z=load(fullfile(p,f),'data');D=z.data;
        imgs=cell(size(D.files));
        for k=1:numel(D.files)
            fn=D.files{k};
            if ~exist(fn,'file')
                [~,name,ext]=fileparts(fn);fn=fullfile(p,[name ext]);
            end
            if ~exist(fn,'file'),errordlg(['Image not found: ' fn]);return;end
            im=imread(fn);if ndims(im)==3,im=rgb2gray(im);end
            imgs{k}=im2double(im);D.files{k}=fn;
        end
        S=D;S.imgs=imgs;S.path=fullfile(p,f);S.dirty=false;
        set(Ediam,'String',num2str(S.diameter));
        set(Esearch,'String',num2str(S.searchRadius));
        set(Etemp,'String',num2str(S.templateRadius));
        set(Cshow,'Value',S.showLabels);draw();
    end
    function exportCSV(~,~)
        if isempty(S.imgs),return;end
        [f,p]=uiputfile('*.csv','Export tracked coordinates','SEM_marker_positions.csv');
        if isequal(f,0),return;end
        N=size(S.xy,1);T=numel(S.imgs);
        id=zeros(N*T,1);frame=id;x=nan(N*T,1);y=x;dx=x;dy=x;
        score=x;state=cell(N*T,1);filename=cell(N*T,1);
        for t=1:T
            for i=1:N
                k=(t-1)*N+i;id(k)=i;frame(k)=t-1;
                x(k)=S.xy(i,1,t);y(k)=S.xy(i,2,t);
                dx(k)=x(k)-S.xy(i,1,1);dy(k)=y(k)-S.xy(i,2,1);
                score(k)=S.scores(i,t);state{k}=S.status{i,t};
                [~,name,ext]=fileparts(S.files{t});filename{k}=[name ext];
            end
        end
        tab=table(id,frame,filename,x,y,dx,dy,score,state, ...
            'VariableNames',{'MarkerID','Frame','Filename','X_px','Y_px', ...
            'dX_px','dY_px','NCC_score','Status'});
        writetable(tab,fullfile(p,f));msg(['CSV exported: ' fullfile(p,f)]);
    end
    function openStrain(~,~)
        if isempty(S.imgs),return;end
        if ~any(S.accepted)
            errordlg('Accept at least one tracking frame before strain analysis.');return;
        end
        % Recreate the analysis from CURRENT tracking coordinates each time.
        % Closing the strain figure must never disable this callback, and
        % edits made in the tracking GUI must appear on the next opening.
        try
            if ~isempty(strainFig) && isgraphics(strainFig,'figure')
                delete(strainFig);
            end
            strainFig=[];
            strainFig=SEMStrainAnalysisIntegrated(S.xy,S.status,S.accepted,S.files,F);
            if ~isempty(strainFig) && isgraphics(strainFig,'figure')
                setappdata(F,'SEMReturnFromStrain',false);
            end
            if ~isempty(strainFig) && isgraphics(strainFig,'figure')
                figure(strainFig);
            end
        catch ME
            strainFig=[];
            errordlg(sprintf('Strain analysis failed: %s',ME.message),'Analysis error');
            fprintf(2,'%s\n',getReport(ME,'extended','hyperlinks','off'));
        end
    end
    function onClose(~,~)
        if S.dirty && ~isempty(S.imgs)
            a=questdlg('Unsaved changes. Save the session before closing?', ...
                'Unsaved changes','Save','Discard','Cancel','Save');
            if strcmp(a,'Cancel')||isempty(a),return;end
            if strcmp(a,'Save')
                saveSession();if S.dirty,return;end
            end
        end
        if ~isempty(strainFig) && isgraphics(strainFig,'figure')
            delete(strainFig);
        end
        delete(F);
    end
end

function F=SEMStrainAnalysisIntegrated(xy,status,accepted,files,trackingFigure)
% Three-node Delaunay constant-strain triangles (CST), reference mesh fixed.
% Image coordinates x right, y DOWN; physical x right, y UP.
% Triangle gradients are calculated in the physical coordinate system.
% No interpolation, local regression, or extrapolation for missing markers.
F=[];
if nargin<5,trackingFigure=[];end
N=size(xy,1); T=size(xy,3);
if N<3 || T<2,errordlg('Need at least three markers and two frames.');return;end
if ~all(accepted)
    answer=questdlg('Not all frames are accepted. Analyze accepted frames only?', ...
        'Unaccepted frames','Accepted only','All available','Cancel','Accepted only');
    if isempty(answer)||strcmp(answer,'Cancel'),return;end
    if strcmp(answer,'Accepted only'),use=logical(accepted);else,use=true(1,T);end
else
    use=true(1,T);
end
ref=[xy(:,1,1),-xy(:,2,1)];
validRef=all(isfinite(ref),2);
if sum(validRef)<3,errordlg('Reference image has fewer than three valid markers.');return;end
refIDs=find(validRef);
try
    triLocal=delaunay(ref(refIDs,1),ref(refIDs,2));
catch ME
    errordlg(['Cannot triangulate reference markers: ' ME.message]);return;
end
tri=refIDs(triLocal);
% Filter poorly conditioned triangles, using minimum angle >= 12 degrees.
keep=false(size(tri,1),1);
for e=1:size(tri,1)
    p=ref(tri(e,:),:);
    d=[norm(p(2,:)-p(3,:)),norm(p(1,:)-p(3,:)),norm(p(1,:)-p(2,:))];
    area=abs(det([p(2,:)-p(1,:);p(3,:)-p(1,:)]))/2;
    cosines=[(d(2)^2+d(3)^2-d(1)^2)/(2*d(2)*d(3)), ...
             (d(1)^2+d(3)^2-d(2)^2)/(2*d(1)*d(3)), ...
             (d(1)^2+d(2)^2-d(3)^2)/(2*d(1)*d(2))];
    ang=acosd(max(-1,min(1,cosines)));
    keep(e)=area>1e-8 && all(isfinite(ang)) && min(ang)>=12;
end
tri=tri(keep,:); E=size(tri,1);
if E<1,errordlg('No well-conditioned Delaunay triangles in reference image.');return;end
R=struct('valid',false(N,T),'local',nan(E,5,T), ...
    'global',nan(T,4),'count',zeros(T,1),'rmse',nan(T,1), ...
    'se',nan(T,2),'ci95',nan(T,2),'dof',nan(T,1));
for t=1:T
    if ~use(t),continue;end
    cur=[xy(:,1,t),-xy(:,2,t)];
    good=validRef & all(isfinite(cur),2);
    if ~isempty(status)
        for k=1:N
            if strcmp(status{k,t},'missing')||strcmp(status{k,t},'untracked')
                good(k)=false;
            end
        end
    end
    R.valid(:,t)=good;R.count(t)=sum(good);
    ids=find(good);
    if numel(ids)>=3
        X=ref(ids,:); U=cur(ids,:)-X;
        D=[ones(numel(ids),1),X-mean(X,1)];
        if rank(D)>=3
            B=D\U;
            G=[B(2,1),B(3,1);B(2,2),B(3,2)];
            R.global(t,:)=[G(1,1),G(2,2),.5*(G(1,2)+G(2,1)), ...
                .5*(G(1,2)-G(2,1))];
            resid=U-D*B;R.rmse(t)=sqrt(mean(sum(resid.^2,2)));
            % OLS coefficient uncertainty, using centered reference coordinates.
            % Exx is coefficient (2,1), Eyy is coefficient (3,2).
            dof=numel(ids)-3;R.dof(t)=dof;
            if dof>0
                invDD=pinv(D'*D);
                s2=sum(resid.^2,1)/dof;
                R.se(t,:)=[sqrt(max(0,s2(1)*invDD(2,2))), ...
                           sqrt(max(0,s2(2)*invDD(3,3)))];
                crit=semCritical95(dof);
                R.ci95(t,:)=crit*R.se(t,:);
            end
        end
    end
    for e=1:E
        idx=tri(e,:);
        if ~all(good(idx)),continue;end
        X=ref(idx,:); U=cur(idx,:)-X;
        D=[ones(3,1),X];
        if rcond(D)<1e-13,continue;end
        B=D\U;
        G=[B(2,1),B(3,1);B(2,2),B(3,2)];
        exx=G(1,1);eyy=G(2,2);
        exy=.5*(G(1,2)+G(2,1));
        wxy=.5*(G(1,2)-G(2,1));
        R.local(e,1:4,t)=[exx,eyy,exy,wxy];
    end
end
F=figure('Name','SEM Tracker - Strain Analysis','NumberTitle','off', ...
    'Color',[.96 .96 .96],'Units','normalized','Position',[.06 .06 .88 .86], ...
    'CloseRequestFcn',@closeAnalysis, ...
    'DefaultAxesFontName','Arial','DefaultTextFontName','Arial', ...
    'DefaultUicontrolFontName','Arial');
% Explicit way back to tracking, without discarding tracking coordinates.
uicontrol(F,'Style','pushbutton','String','Return to tracking', ...
    'Units','normalized','Position',[.035 .905 .16 .030], ...
    'FontName','Arial','FontSize',10,'Callback',@closeAnalysis);
uicontrol(F,'Style','text', ...
    'String','SEM fiducial marker tracker by Shaolou Wei, Sc.D. and Dr.-Ing Xinren Chen, MPI-SusMat', ...
    'Units','normalized','Position',[.03 .937 .94 .042], ...
    'BackgroundColor',[.96 .96 .96],'ForegroundColor',[.12 .16 .23], ...
    'FontName','Arial','FontWeight','bold','FontSize',13,'HorizontalAlignment','center');
ax=axes('Parent',F,'Units','normalized','Position',[.06 .12 .65 .77]);
ctrl=uipanel('Parent',F,'Title','Strain controls','FontName','Arial', ...
    'Units','normalized','Position',[.745 .06 .245 .84]);
label('Strain component',.950);
component=uicontrol(ctrl,'Style','popupmenu','String', ...
    {'epsilon xx','epsilon yy','epsilon xy','omega xy','von Mises equivalent'}, ...
    'Units','normalized','Position',[.06 .917 .88 .034],'Callback',@redraw);
label('Milling step (0-based)',.886);
step=uicontrol(ctrl,'Style','slider','Min',1,'Max',T,'Value',min(2,T), ...
    'SliderStep',[1/max(1,T-1),1/max(1,T-1)], ...
    'Units','normalized','Position',[.06 .852 .88 .029],'Callback',@redraw);
stepText=uicontrol(ctrl,'Style','text','String','', ...
    'Units','normalized','Position',[.06 .822 .88 .025]);
label('Colormap',.794);
cmap=uicontrol(ctrl,'Style','popupmenu','String', ...
    {'bluered','bluered2','bluecyanred','parula','jet','hot','cool','gray','turbo (if available)'}, ...
    'Units','normalized','Position',[.06 .760 .88 .034],'Callback',@redraw);
label('Color limits (% strain, degrees rotation)',.731);
lo=uicontrol(ctrl,'Style','edit','String','-0.5','Units','normalized', ...
    'Position',[.06 .699 .4 .032],'Callback',@redraw);
hi=uicontrol(ctrl,'Style','edit','String','0.5','Units','normalized', ...
    'Position',[.54 .699 .4 .032],'Callback',@redraw);
auto=uicontrol(ctrl,'Style','checkbox','String','Auto color limits', ...
    'Value',1,'Units','normalized','Position',[.06 .663 .88 .030], ...
    'Callback',@redraw);
overlay=uicontrol(ctrl,'Style','checkbox','String','Overlay on SEM micrograph', ...
    'Value',1,'Units','normalized','Position',[.06 .631 .88 .030], ...
    'Callback',@redraw);
label('Strain overlay opacity',.606);
alphaSlider=uicontrol(ctrl,'Style','slider','Min',0,'Max',1,'Value',.55, ...
    'Units','normalized','Position',[.06 .578 .68 .026], ...
    'Callback',@redraw);
alphaText=uicontrol(ctrl,'Style','text','String','55%', ...
    'Units','normalized','Position',[.76 .574 .18 .028]);
mesh=uicontrol(ctrl,'Style','checkbox','String','Show triangular boundaries', ...
    'Value',0,'Units','normalized','Position',[.06 .542 .88 .028], ...
    'Callback',@redraw);
uicontrol(ctrl,'Style','text','String','Mesh line width (pt)', ...
    'Units','normalized','Position',[.06 .509 .40 .026], ...
    'HorizontalAlignment','left');
meshWidth=uicontrol(ctrl,'Style','edit','String','0.5', ...
    'Units','normalized','Position',[.06 .478 .40 .030], ...
    'Callback',@redraw);
uicontrol(ctrl,'Style','text','String','Mesh line opacity', ...
    'Units','normalized','Position',[.54 .509 .40 .026], ...
    'HorizontalAlignment','left');
meshAlpha=uicontrol(ctrl,'Style','slider','Min',0,'Max',1,'Value',.70, ...
    'Units','normalized','Position',[.54 .478 .29 .028], ...
    'Callback',@redraw);
meshAlphaText=uicontrol(ctrl,'Style','text','String','70%', ...
    'Units','normalized','Position',[.84 .478 .10 .028]);
showAxes=uicontrol(ctrl,'Style','checkbox','String','Show X/Y axes', ...
    'Value',1,'Units','normalized','Position',[.06 .440 .88 .030], ...
    'Callback',@redraw);
label('Von Mises assumption',.410);
vmMode=uicontrol(ctrl,'Style','popupmenu', ...
    'String',{'Plane strain (ezz = 0)','Plane stress (elastic)'}, ...
    'Units','normalized','Position',[.06 .377 .88 .032], ...
    'Callback',@redraw);
label('Poisson ratio (plane stress)',.347);
nuEdit=uicontrol(ctrl,'Style','edit','String','0.30', ...
    'Units','normalized','Position',[.06 .314 .88 .032],'Callback',@redraw);
button('Strain frequency distribution analysis',.272,@openDistribution);
button('Global strain history',.226,@plotGlobal);
button('Export global strains (CSV)',.180,@exportGlobal);
button('Export element strains (CSV)',.134,@exportLocal);
button('Export current map (PNG)',.088,@exportMap);
button('Export all maps (PNG)',.042,@exportAll);
helpText=uicontrol(ctrl,'Style','text','Units','normalized', ...
    'Position',[.05 .004 .9 .032],'HorizontalAlignment','left', ...
    'FontSize',8,'String',sprintf(['Fixed Delaunay CST mesh; 3 markers/element.\n', ...
    'Missing markers invalidate their triangles.']));
redraw();
    function closeAnalysis(~,~)
        % Delete only the analysis window. The main tracking GUI and its
        % saved session stay alive, and analysis can be reopened at any time.
        if isgraphics(F,'figure'),delete(F);end
        if ~isempty(trackingFigure) && isgraphics(trackingFigure,'figure')
            setappdata(trackingFigure,'SEMReturnFromStrain',true);
            figure(trackingFigure);
        end
    end
    function label(str,y)
        uicontrol(ctrl,'Style','text','String',str,'Units','normalized', ...
            'Position',[.06 y .88 .026],'HorizontalAlignment','left');
    end
    function button(str,y,cb)
        uicontrol(ctrl,'Style','pushbutton','String',str,'Units','normalized', ...
            'Position',[.06 y .88 .040],'Callback',cb);
    end
    function [t,c,scale]=selection()
        t=max(1,min(T,round(get(step,'Value'))));set(step,'Value',t);
        c=get(component,'Value');
        scale=100;
        if c==4,scale=180/pi;end
    end
    function z=elementValues(t,c)
        if c<5
            z=R.local(:,c,t);
            return;
        end
        a=R.local(:,1,t);b=R.local(:,2,t);g=R.local(:,3,t);
        nu=str2double(get(nuEdit,'String'));
        if ~isfinite(nu)||nu<=-1||nu>=.5
            nu=.3;set(nuEdit,'String','0.30');
        end
        if get(vmMode,'Value')==2
            ezz=-nu/(1-nu)*(a+b);
        else
            ezz=zeros(size(a));
        end
        % von Mises equivalent strain = sqrt(2/3 dev(e):dev(e)).
        % This is the measured relaxation strain, NOT accumulated plastic strain.
        meanE=(a+b+ezz)/3;
        z=sqrt(max(0,2/3*((a-meanE).^2+(b-meanE).^2+ ...
            (ezz-meanE).^2+2*g.^2)));
    end
    function cm=selectedMap(c)
        choices={'bluered','bluered2','bluecyanred','parula','jet','hot','cool','gray','turbo'};
        name=choices{get(cmap,'Value')};
        if any(strcmp(name,{'bluered','bluered2','bluecyanred'}))
            full=feval(name,256);
            if c==5,cm=full(129:end,:);else,cm=full;end
        else
            try,cm=feval(name,256);catch,cm=parula(256);end
        end
    end
    function redraw(~,~)
        [t,c,scale]=selection();
        set(stepText,'String',sprintf('Step %02d / %02d',t-1,T-1));
        set(alphaText,'String',sprintf('%d%%',round(get(alphaSlider,'Value')*100)));
        set(meshAlphaText,'String',sprintf('%d%%',round(get(meshAlpha,'Value')*100)));
        lineWidth=str2double(get(meshWidth,'String'));
        if ~isfinite(lineWidth)||lineWidth<=0||lineWidth>20
            lineWidth=0.5;set(meshWidth,'String','0.5');
        end
        cla(ax);hold(ax,'on');
        doOverlay=logical(get(overlay,'Value'));
        if doOverlay
            try
                I=imread(files{t});
                if ndims(I)==3,I=rgb2gray(I);end
                I=im2double(I);
                % Truecolor RGB prevents the strain colormap recoloring SEM.
                I=repmat(I,[1 1 3]);
                image(ax,[1 size(I,2)],[1 size(I,1)],I);
                set(ax,'YDir','reverse');
            catch ME
                warning('SEMTracker:Background','SEM background unavailable: %s',ME.message);
                doOverlay=false;
            end
        end
        z=elementValues(t,c)*scale;
        good=all(isfinite(reshape(R.local(:,1:4,t),E,4)),2)&isfinite(z);
        active=find(good);
        if ~isempty(active)
            if doOverlay
                V=[xy(:,1,t),xy(:,2,t)];
            else
                V=[ref(:,1),-ref(:,2)];
            end
            edges='none';
            if get(mesh,'Value'),edges=[.2 .2 .2];end
            h=patch('Parent',ax,'Faces',tri(active,:),'Vertices',V, ...
                'FaceVertexCData',z(active),'FaceColor','flat', ...
                'EdgeColor',edges,'LineWidth',lineWidth, ...
                'EdgeAlpha',get(meshAlpha,'Value'));
            if doOverlay,set(h,'FaceAlpha',get(alphaSlider,'Value'));end
        end
        axis(ax,'image');
        if doOverlay
            xlim(ax,[.5 size(I,2)+.5]);ylim(ax,[.5 size(I,1)+.5]);
            set(ax,'YDir','reverse');
        else
            set(ax,'YDir','reverse');axis(ax,'tight');
        end
        xlabel(ax,'X (pixels)');ylabel(ax,'Image Y (pixels, downward)');
        if get(showAxes,'Value')
            set(ax,'XColor',[.15 .15 .15],'YColor',[.15 .15 .15]);
            set(get(ax,'XLabel'),'Visible','on');
            set(get(ax,'YLabel'),'Visible','on');
        else
            set(ax,'XColor','none','YColor','none');
            set(get(ax,'XLabel'),'Visible','off');
            set(get(ax,'YLabel'),'Visible','off');
        end
        names={'\varepsilon_{xx}','\varepsilon_{yy}','\varepsilon_{xy}', ...
            '\omega_{xy}','\varepsilon_{\mathrm{VM}}'};
        title(ax,sprintf('$%s$ | step %02d | %d/%d valid elements', ...
            names{c},t-1,numel(active),E),'Interpreter','latex');
        colormap(ax,selectedMap(c));
        vals=z(good);
        if get(auto,'Value')
            if isempty(vals),lim=[-1 1];
            elseif c==5
                lim=[0 max(vals)];
                if lim(2)<=0,lim(2)=.001;end
            else
                bound=max(abs(vals));
                if bound<1e-10,bound=.001;end
                lim=[-bound bound];
            end
            set(lo,'String',sprintf('%.5g',lim(1)));
            set(hi,'String',sprintf('%.5g',lim(2)));
        else
            lim=[str2double(get(lo,'String')),str2double(get(hi,'String'))];
            if ~all(isfinite(lim))||lim(2)<=lim(1),lim=[-1 1];end
        end
        caxis(ax,lim);cb=colorbar(ax);
        if c==4,ylabel(cb,'degrees');else,ylabel(cb,'%');end
        hold(ax,'off');drawnow limitrate;
    end
    function openDistribution(~,~)
        % Elementwise CST strains; lognormal fitting is performed on positive
        % magnitudes for signed quantities, never on negative signed values.
        H=figure('Name','SEM strain frequency distribution','NumberTitle','off', ...
            'Color','w','Units','normalized','Position',[.16 .16 .70 .68], ...
            'DefaultAxesFontName','Arial','DefaultTextFontName','Arial', ...
            'DefaultUicontrolFontName','Arial');
        da=axes('Parent',H,'Units','normalized','Position',[.09 .17 .62 .73]);
        hp=uipanel('Parent',H,'Title','Distribution controls','FontName','Arial', ...
            'Units','normalized','Position',[.74 .10 .245 .80]);
        uicontrol(hp,'Style','text','String','Strain component', ...
            'Units','normalized','Position',[.06 .92 .88 .045], ...
            'HorizontalAlignment','left');
        dc=uicontrol(hp,'Style','popupmenu','String', ...
            {'epsilon xx','epsilon yy','epsilon xy','von Mises equivalent'}, ...
            'Units','normalized','Position',[.06 .865 .88 .055], ...
            'Value',min(get(component,'Value'),4),'Callback',@updateDistribution);
        % Component 4 here means von Mises, not rotation.
        if get(component,'Value')==5,set(dc,'Value',4);end
        uicontrol(hp,'Style','text','String','Milling step (0-based)', ...
            'Units','normalized','Position',[.06 .803 .88 .045], ...
            'HorizontalAlignment','left');
        ds=uicontrol(hp,'Style','slider','Min',1,'Max',T, ...
            'Value',round(get(step,'Value')), ...
            'SliderStep',[1/max(1,T-1),1/max(1,T-1)], ...
            'Units','normalized','Position',[.06 .758 .88 .044], ...
            'Callback',@updateDistribution);
        dst=uicontrol(hp,'Style','text','String','', ...
            'Units','normalized','Position',[.06 .715 .88 .038]);
        uicontrol(hp,'Style','text','String','Histogram bin width (% strain)', ...
            'Units','normalized','Position',[.06 .650 .88 .050], ...
            'HorizontalAlignment','left');
        db=uicontrol(hp,'Style','edit','String','0.02', ...
            'Units','normalized','Position',[.06 .602 .88 .052], ...
            'Callback',@updateDistribution);
        magnitude=uicontrol(hp,'Style','checkbox', ...
            'String','Use absolute strain for signed components', ...
            'Value',1,'Units','normalized','Position',[.06 .526 .90 .060], ...
            'Callback',@updateDistribution);
        weight=uicontrol(hp,'Style','checkbox','String','Area-weighted frequency', ...
            'Value',0,'Units','normalized','Position',[.06 .465 .88 .055], ...
            'Callback',@updateDistribution);
        fitToggle=uicontrol(hp,'Style','checkbox','String','Show lognormal fit', ...
            'Value',1,'Units','normalized','Position',[.06 .404 .88 .055], ...
            'Callback',@updateDistribution);
        uicontrol(hp,'Style','pushbutton','String','Export distribution + fit (CSV)', ...
            'Units','normalized','Position',[.06 .310 .88 .067], ...
            'Callback',@exportDistribution);
        uicontrol(hp,'Style','pushbutton','String','Export distribution figure (PNG)', ...
            'Units','normalized','Position',[.06 .232 .88 .067], ...
            'Callback',@exportDistributionFigure);
        note=uicontrol(hp,'Style','text','String','', ...
            'Units','normalized','Position',[.06 .018 .88 .196], ...
            'HorizontalAlignment','left','FontSize',9);
        last=struct('edges',[],'centers',[],'frequency',[], ...
            'fitBin',[],'curveX',[],'curveY',[],'mu',NaN,'sigma',NaN, ...
            'n',0,'step',0,'component','','weighted',false,'magnitude',false);
        updateDistribution();
        function updateDistribution(~,~)
            if ~ishandle(H),return;end
            t=max(1,min(T,round(get(ds,'Value'))));set(ds,'Value',t);
            set(dst,'String',sprintf('Step %02d / %02d',t-1,T-1));
            k=get(dc,'Value');
            indices=[1 2 3 5]; c=indices(k);
            vals=100*elementValues(t,c);
            signed=c~=5;
            useMagnitude=signed && logical(get(magnitude,'Value'));
            set(magnitude,'Enable',ternary(signed,'on','off'));
            if useMagnitude,vals=abs(vals);end
            widths=str2double(get(db,'String'));
            if ~isfinite(widths)||widths<=0
                widths=.02;set(db,'String','0.02');
            end
            p1=ref(tri(:,1),:);p2=ref(tri(:,2),:);p3=ref(tri(:,3),:);
            area=.5*abs((p2(:,1)-p1(:,1)).*(p3(:,2)-p1(:,2))- ...
                (p3(:,1)-p1(:,1)).*(p2(:,2)-p1(:,2)));
            valid=isfinite(vals)&isfinite(area)&area>0;
            v=vals(valid);a=area(valid);
            cla(da);hold(da,'on');
            last=struct('edges',[],'centers',[],'frequency',[], ...
                'fitBin',[],'curveX',[],'curveY',[],'mu',NaN,'sigma',NaN, ...
                'n',numel(v),'step',t-1,'component','', 'weighted',logical(get(weight,'Value')), ...
                'magnitude',useMagnitude);
            componentNames={'exx','eyy','exy','von_mises'};
            last.component=componentNames{k};
            if isempty(v)
                title(da,'No valid strain elements at this step');
                set(note,'String','No valid elements; nothing to fit.');
                hold(da,'off');return;
            end
            if get(weight,'Value'),w=a/sum(a);else,w=ones(size(v))/numel(v);end
            minV=min(v);maxV=max(v);
            % Align bins to multiples of the requested bin width.
            lower=floor(minV/widths)*widths;
            upper=ceil(maxV/widths)*widths;
            if upper<=lower,upper=lower+widths;end
            nBins=max(1,round((upper-lower)/widths));
            if nBins>3000
                set(note,'String','Bin width is too small (>3000 bins). Increase it.');
                hold(da,'off');return;
            end
            edges=lower+(0:nBins)*widths;
            edges(end)=max(edges(end),maxV+max(eps(maxV),1e-12));
            [~,~,bin]=histcounts(v,edges);
            freq=accumarray(bin(bin>0),w(bin>0),[nBins 1],@sum,0);
            centers=(edges(1:end-1)+edges(2:end))/2;
            bar(da,centers,freq,1,'FaceColor',[.40 .58 .75], ...
                'EdgeColor',[.2 .3 .4],'DisplayName','Observed relative frequency');
            fitBin=nan(nBins,1);curveX=[];curveY=[];mu=NaN;sigma=NaN;
            positive=v>0;
            if get(fitToggle,'Value') && (~signed||useMagnitude) && sum(positive)>=3
                wp=w(positive);wp=wp/sum(wp);
                lv=log(v(positive));mu=sum(wp.*lv);
                sigma=sqrt(sum(wp.*(lv-mu).^2));
                if sigma>1e-12
                    % Exact integrated lognormal probability per histogram bin.
                    Fcdf=@(x) .5*(1+erf((log(max(x,realmin))-mu)/(sigma*sqrt(2))));
                    fitBin=diff(Fcdf(max(edges,0)))';
                    fitBin=fitBin*sum(w(positive));
                    curveX=linspace(max(0,lower),upper,600)';
                    curveY=exp(-.5*((log(max(curveX,realmin))-mu)/sigma).^2) ...
                        ./ (max(curveX,realmin)*sigma*sqrt(2*pi));
                    curveY=curveY*widths*sum(w(positive));
                    plot(da,curveX,curveY,'-','Color',[.75 .20 .15], ...
                        'LineWidth',1.8,'DisplayName','Lognormal fit (bin probability)');
                end
            end
            last.edges=edges(:);last.centers=centers(:);last.frequency=freq;
            last.fitBin=fitBin;last.curveX=curveX;last.curveY=curveY;
            last.mu=mu;last.sigma=sigma;
            xlabel(da,'Strain (%)');ylabel(da,'Relative frequency per bin');
            title(da,sprintf('%s | milling step %02d | %d elements', ...
                last.component,t-1,numel(v)),'Interpreter','none');
            legend(da,'Location','best');grid(da,'on');hold(da,'off');
            if signed && ~useMagnitude
                set(note,'String',sprintf(['Signed distribution shown. Standard lognormal ', ...
                    'requires positive values; enable absolute strain to fit.\nN = %d'],numel(v)));
            elseif ~isfinite(sigma)
                set(note,'String',sprintf(['N = %d. Lognormal fit unavailable ', ...
                    '(need at least 3 positive, nonidentical values).'],numel(v)));
            else
                set(note,'String',sprintf('N = %d elements\nlognormal mu = %.5g\nsigma = %.5g', ...
                    numel(v),mu,sigma));
            end
        end
        function exportDistribution(~,~)
            updateDistribution();
            if isempty(last.edges),errordlg('No distribution to export.');return;end
            [f,pth]=uiputfile('*.csv','Save strain histogram and lognormal fit', ...
                sprintf('SEM_distribution_step_%02d_%s.csv',last.step,last.component));
            if isequal(f,0),return;end
            lower_edge=last.edges(1:end-1);upper_edge=last.edges(2:end);
            bin_center=last.centers;relative_frequency=last.frequency;
            fitted_bin_probability=last.fitBin;
            writetable(table(lower_edge,upper_edge,bin_center,relative_frequency, ...
                fitted_bin_probability),fullfile(pth,f));
            [~,stem,~]=fileparts(f);
            if ~isempty(last.curveX)
                strain_percent=last.curveX;fitted_relative_frequency=last.curveY;
                writetable(table(strain_percent,fitted_relative_frequency), ...
                    fullfile(pth,[stem '_fitted_curve.csv']));
            end
            fid=fopen(fullfile(pth,[stem '_parameters.txt']),'w');
            if fid>=0
                fprintf(fid,'Milling step: %d\nComponent: %s\nElements: %d\n', ...
                    last.step,last.component,last.n);
                fprintf(fid,'Absolute strain: %d\nArea weighted: %d\n', ...
                    last.magnitude,last.weighted);
                fprintf(fid,'Bin width (percent strain): %.10g\n', ...
                    last.edges(2)-last.edges(1));
                fprintf(fid,'Lognormal mu (log of percent strain): %.12g\n',last.mu);
                fprintf(fid,'Lognormal sigma: %.12g\n',last.sigma);
                fclose(fid);
            end
        end
        function exportDistributionFigure(~,~)
            [f,pth]=uiputfile('*.png','Save distribution figure', ...
                sprintf('SEM_distribution_step_%02d.png',last.step));
            if isequal(f,0),return;end
            figureOut=figure('Visible','off','Color','w','Position',[100 100 1000 700]);
            copyAx=copyobj(da,figureOut);
            set(copyAx,'Units','normalized','Position',[.12 .12 .80 .80]);
            print(figureOut,fullfile(pth,f),'-dpng','-r300');close(figureOut);
        end
        function out=ternary(condition,a,b)
            if condition,out=a;else,out=b;end
        end
    end
    function plotGlobal(~,~)
        % Interactive confidence-interval and spatial-sampling diagnostics.
        gf=figure('Name','Global ring-core strain: uncertainty analysis', ...
            'NumberTitle','off','Color','w','Position',[130 110 1100 720], ...
            'DefaultAxesFontName','Arial','DefaultUicontrolFontName','Arial');
        ga=axes('Parent',gf,'Units','normalized','Position',[.09 .19 .66 .70]);
        uicontrol(gf,'Style','text','String','Uncertainty method', ...
            'Units','normalized','Position',[.78 .85 .20 .035], ...
            'BackgroundColor','w','HorizontalAlignment','left');
        method=uicontrol(gf,'Style','popupmenu','Units','normalized', ...
            'Position',[.78 .81 .20 .045], ...
            'String',{'OLS standard error','Marker bootstrap','Spatial block bootstrap'}, ...
            'Callback',@refreshGlobal);
        uicontrol(gf,'Style','text','String','Confidence interval', ...
            'Units','normalized','Position',[.78 .74 .20 .035], ...
            'BackgroundColor','w','HorizontalAlignment','left');
        confidence=uicontrol(gf,'Style','popupmenu','Units','normalized', ...
            'Position',[.78 .70 .20 .045],'String',{'95%','68%','99%'}, ...
            'Callback',@refreshGlobal);
        showError=uicontrol(gf,'Style','checkbox','String','Show error bars', ...
            'Value',1,'BackgroundColor','w','Units','normalized', ...
            'Position',[.78 .63 .20 .05],'Callback',@refreshGlobal);
        fixedSubset=uicontrol(gf,'Style','checkbox','String','Common-marker subset', ...
            'Value',0,'BackgroundColor','w','Units','normalized', ...
            'Position',[.78 .57 .20 .05],'Callback',@refreshGlobal);
        showRotation=uicontrol(gf,'Style','checkbox','String','Plot omega xy (degrees)', ...
            'Value',0,'BackgroundColor','w','Units','normalized', ...
            'Position',[.78 .525 .20 .04],'Callback',@refreshGlobal);
        uicontrol(gf,'Style','text','String','Bootstrap replicates', ...
            'Units','normalized','Position',[.78 .485 .20 .035], ...
            'BackgroundColor','w','HorizontalAlignment','left');
        repeats=uicontrol(gf,'Style','edit','String','500', ...
            'Units','normalized','Position',[.78 .445 .20 .04], ...
            'Callback',@refreshGlobal);
        uicontrol(gf,'Style','pushbutton','String','Export plotted data (CSV)', ...
            'Units','normalized','Position',[.78 .35 .20 .055], ...
            'Callback',@exportPlotGlobal);
        uicontrol(gf,'Style','pushbutton','String','Export plot (PNG)', ...
            'Units','normalized','Position',[.78 .28 .20 .055], ...
            'Callback',@exportGlobalPlotPNG);
        countAx=axes('Parent',gf,'Units','normalized','Position',[.09 .07 .66 .075]);
        info=uicontrol(gf,'Style','text','String','', ...
            'Units','normalized','Position',[.78 .06 .20 .18], ...
            'BackgroundColor','w','HorizontalAlignment','left');
        cacheKey=''; cacheData=[]; plotted=[];
        refreshGlobal();
        function refreshGlobal(~,~)
            methodId=get(method,'Value');
            ciOptions=[.95 .68 .99]; ci=ciOptions(get(confidence,'Value'));
            nrep=str2double(get(repeats,'String'));
            if ~isfinite(nrep),nrep=500;end
            nrep=max(100,min(5000,round(nrep)));
            set(repeats,'String',num2str(nrep));
            common=logical(get(fixedSubset,'Value'));
            key=sprintf('%d_%.3f_%d_%d',methodId,ci,nrep,common);
            if ~strcmp(cacheKey,key)
                cacheData=semGlobalUncertainty(ref,xy,status,use,R.valid, ...
                    methodId,ci,nrep,common);
                cacheKey=key;
            end
            plotted=cacheData;
            tt=(0:T-1)';
            cla(ga);hold(ga,'on');
            componentLabels={'epsilon xx','epsilon yy','epsilon xy'};
            colors=[0 .447 .741;.85 .325 .098;.466 .674 .188];
            markers={'o','s','^'};
            for c=1:3
                y=plotted.strain(:,c)*100;
                low=(plotted.strain(:,c)-plotted.lower(:,c))*100;
                high=(plotted.upper(:,c)-plotted.strain(:,c))*100;
                if get(showError,'Value')
                    valid=isfinite(y)&isfinite(low)&isfinite(high)&low>=0&high>=0;
                    if any(valid)
                        errorbar(ga,tt(valid),y(valid),low(valid),high(valid), ...
                            ['-' markers{c}],'Color',colors(c,:), ...
                            'LineWidth',1.3,'MarkerSize',5,'CapSize',5, ...
                            'DisplayName',componentLabels{c});
                    end
                    if any(~valid & isfinite(y))
                        plot(ga,tt(~valid & isfinite(y)),y(~valid & isfinite(y)), ...
                            ['-' markers{c}],'Color',colors(c,:), ...
                            'DisplayName',componentLabels{c});
                    end
                else
                    plot(ga,tt,y,['-' markers{c}],'Color',colors(c,:), ...
                        'LineWidth',1.4,'MarkerSize',5, ...
                        'DisplayName',componentLabels{c});
                end
            end
            if get(showRotation,'Value')
                y=plotted.strain(:,4)*180/pi;
                plot(ga,tt,y,'--d','Color',[.49 .18 .56], ...
                    'LineWidth',1.3,'MarkerSize',5,'DisplayName','omega xy (deg)');
                ylabel(ga,'Strain (%) / rotation (degrees)');
            else
                ylabel(ga,'Engineering strain (%)');
            end
            grid(ga,'on');xlabel(ga,'Milling step');
            title(ga,'Global affine strain relative to reference image 00');
            legend(ga,'show','Location','best','Interpreter','none');
            if T>1,xlim(ga,[0 T-1]);end
            cla(countAx);bar(countAx,tt,plotted.count,.65, ...
                'FaceColor',[.5 .5 .5]);
            ylabel(countAx,'N markers');xlabel(countAx,'Milling step');
            if T>1,xlim(countAx,[-.5 T-.5]);end
            set(info,'String',sprintf(['OLS: independent, equal-variance ', ...
                'errors assumed.\nBootstrap: sampling sensitivity, not ', ...
                'pure tracking precision.\nN valid: %d to %d'], ...
                min(plotted.count),max(plotted.count)));
        end
        function exportPlotGlobal(~,~)
            if isempty(plotted),return;end
            [f,pth]=uiputfile('*.csv','Export global strain with confidence intervals', ...
                'SEM_global_strain_uncertainty.csv');
            if isequal(f,0),return;end
            milling_step=(0:T-1)';n_markers=plotted.count;
            exx=plotted.strain(:,1);eyy=plotted.strain(:,2);
            exy=plotted.strain(:,3);omega_xy=plotted.strain(:,4);
            exx_lower=plotted.lower(:,1);exx_upper=plotted.upper(:,1);
            eyy_lower=plotted.lower(:,2);eyy_upper=plotted.upper(:,2);
            exy_lower=plotted.lower(:,3);exy_upper=plotted.upper(:,3);
            omega_xy_lower=plotted.lower(:,4);omega_xy_upper=plotted.upper(:,4);
            fit_RMSE_px=plotted.rmse;
            writetable(table(milling_step,n_markers,exx,exx_lower,exx_upper, ...
                eyy,eyy_lower,eyy_upper,exy,exy_lower,exy_upper, ...
                omega_xy,omega_xy_lower,omega_xy_upper,fit_RMSE_px),fullfile(pth,f));
        end
        function exportGlobalPlotPNG(~,~)
            [f,pth]=uiputfile('*.png','Export global strain history', ...
                'SEM_global_strain_uncertainty.png');
            if isequal(f,0),return;end
            print(gf,fullfile(pth,f),'-dpng','-r300');
        end
    end
    function exportGlobal(~,~)
        [f,p]=uiputfile('*.csv','Save global strain history','SEM_global_strains.csv');
        if isequal(f,0),return;end
        milling_step=(0:T-1)';accepted_frame=accepted(:);n_markers=R.count;
        exx=R.global(:,1);eyy=R.global(:,2);exy=R.global(:,3);
        omega_xy=R.global(:,4);fit_RMSE_px=R.rmse;
        exx_SE=R.se(:,1);eyy_SE=R.se(:,2);
        exx_CI95_lower=exx-R.ci95(:,1);exx_CI95_upper=exx+R.ci95(:,1);
        eyy_CI95_lower=eyy-R.ci95(:,2);eyy_CI95_upper=eyy+R.ci95(:,2);
        writetable(table(milling_step,accepted_frame,n_markers,exx,eyy,exy, ...
            omega_xy,fit_RMSE_px,exx_SE,eyy_SE,exx_CI95_lower, ...
            exx_CI95_upper,eyy_CI95_lower,eyy_CI95_upper),fullfile(p,f));
    end
    function exportLocal(~,~)
        [f,p]=uiputfile('*.csv','Save triangle strains','SEM_element_strains.csv');
        if isequal(f,0),return;end
        [eid,tt]=ndgrid((1:E)',(0:T-1)');
        element_id=eid(:);milling_step=tt(:);
        node1=repmat(tri(:,1),T,1);node2=repmat(tri(:,2),T,1);
        node3=repmat(tri(:,3),T,1);
        exx=reshape(R.local(:,1,:),[],1);
        eyy=reshape(R.local(:,2,:),[],1);
        exy=reshape(R.local(:,3,:),[],1);
        omega_xy=reshape(R.local(:,4,:),[],1);
        von_mises=nan(E*T,1);
        for t=1:T
            idx=(t-1)*E+(1:E);
            von_mises(idx)=elementValues(t,5);
        end
        valid_element=isfinite(exx);
        writetable(table(element_id,milling_step,node1,node2,node3, ...
            valid_element,exx,eyy,exy,omega_xy,von_mises),fullfile(p,f));
    end
    function exportMap(~,~)
        [f,p]=uiputfile('*.png','Export current strain map','SEM_strain_map.png');
        if isequal(f,0),return;end
        savePNG(fullfile(p,f));
    end
    function savePNG(fn)
        fig=figure('Visible','off','Color','w','Position',[100 100 1100 800]);
        a2=copyobj(ax,fig);
        set(a2,'Units','normalized','Position',[.10 .10 .78 .82]);
        colormap(a2,colormap(ax));caxis(a2,caxis(ax));
        colorbar(a2);
        print(fig,fn,'-dpng','-r300');close(fig);
    end
    function exportAll(~,~)
        folder=uigetdir(pwd,'Select folder for all strain maps');
        if isequal(folder,0),return;end
        t0=get(step,'Value');c0=get(component,'Value');
        names={'exx','eyy','exy','omega_xy','von_mises'};
        for t=1:T
            if ~use(t),continue;end
            set(step,'Value',t);
            for c=1:5
                set(component,'Value',c);redraw();
                savePNG(fullfile(folder,sprintf('step_%02d_%s.png',t-1,names{c})));
            end
        end
        set(step,'Value',t0);set(component,'Value',c0);redraw();
        msgbox('All available strain maps exported.');
    end
end

function map = bluered(n)
% BLUERED Blue-white-red diverging colormap sampled from supplied figure.
%   MAP = BLUERED(N) returns an N-by-3 RGB colormap.
%   BLUERED defaults to 256 entries. Negative -> blue, zero -> white,
%   positive -> red when color limits are symmetric about zero.
%   Colors were sampled from a JPEG figure and are approximate.
if nargin < 1 || isempty(n)
    n = 256;
end
validateattributes(n,{'numeric'},{'scalar','integer','positive','finite'},mfilename,'n');
anchors = [ ...
    0.25098039 0.37647059 0.52941176;
    0.41960784 0.51372549 0.64705882;
    0.60392157 0.67450980 0.76862745;
    0.77647059 0.81176471 0.84705882;
    0.95686275 0.94901961 0.96078431;
    0.86666667 0.75294118 0.76862745;
    0.76862745 0.56862745 0.58823529;
    0.68627451 0.36470588 0.37254902;
    0.57647059 0.27058824 0.27058824];
x = linspace(0,1,size(anchors,1));
map = interp1(x,anchors,linspace(0,1,n),'linear');
map = max(0,min(1,map));
end

function map = bluered2(n)
% Diverging cool-blue / warm-red palette digitized approximately from
% user-supplied colorbar image; colors ordered low -> high.
if nargin<1||isempty(n),n=256;end
anchors=[114 144 241;145 174 255;175 196 253;201 213 242; ...
    220 218 217;238 205 181;239 177 146;234 145 112;216 107 79;195 55 50]/255;
map=interp1(linspace(0,1,size(anchors,1)),anchors,linspace(0,1,n),'linear');
map=max(0,min(1,map));
end

function map = bluecyanred(n)
% Blue-cyan-yellow-orange-red palette from user-supplied colorbar.
if nargin<1||isempty(n),n=256;end
anchors=[31 9 121;32 74 177;54 154 206;130 239 220; ...
    253 253 236;238 208 73;214 127 22;173 37 5;84 0 23]/255;
map=interp1(linspace(0,1,size(anchors,1)),anchors,linspace(0,1,n),'linear');
map=max(0,min(1,map));
end

function crit=semCritical95(dof)
% Two-sided Student-t critical value, Statistics Toolbox not required.
if dof<=0,crit=NaN;return;end
try
    crit=tinv(.975,dof);
catch
    % Inverse regularized incomplete beta gives t quantile.
    q=betaincinv(.05,dof/2,.5);
    crit=sqrt(dof*(1-q)/q);
end
end

function z=semNormalQuantile(p)
z=sqrt(2)*erfinv(2*p-1);
end

function q=semQuantile(x,p)
x=sort(x(isfinite(x)));
if isempty(x),q=NaN;return;end
v=1+(numel(x)-1)*p;lo=floor(v);hi=ceil(v);
q=x(lo)+(v-lo)*(x(hi)-x(lo));
end

function out=semGlobalUncertainty(ref,xy,status,use,valid,method,ci,nrep,common)
% OLS confidence intervals or bootstrap percentile intervals.
% Bootstraps resample paired (u,v) nodal displacements, preserving covariance.
T=size(xy,3);N=size(xy,1);
out.strain=nan(T,4);out.lower=nan(T,4);out.upper=nan(T,4);
out.count=zeros(T,1);out.rmse=nan(T,1);
commonIDs=all(valid(:,logical(use)),2);
for t=1:T
    if ~use(t),continue;end
    ids=find(valid(:,t) & (~common | commonIDs));
    out.count(t)=numel(ids);
    if numel(ids)<4,continue;end
    X=ref(ids,:);cur=[xy(ids,1,t),-xy(ids,2,t)];U=cur-X;
    D=[ones(numel(ids),1),X-mean(X,1)];
    if rank(D)<3,continue;end
    B=D\U;res=U-D*B;
    out.strain(t,:)=[B(2,1),B(3,2), ...
        .5*(B(3,1)+B(2,2)),.5*(B(3,1)-B(2,2))];
    out.rmse(t)=sqrt(mean(sum(res.^2,2)));
    if method==1
        dof=numel(ids)-3;
        covD=pinv(D'*D);
        sxx=sum(res(:,1).^2)/dof;syy=sum(res(:,2).^2)/dof;
        sxy=sum(res(:,1).*res(:,2))/dof;
        % Covariance of the two fitted displacement components is retained.
        vxy=.25*(sxx*covD(3,3)+syy*covD(2,2)+2*sxy*covD(3,2));
        vrot=.25*(sxx*covD(3,3)+syy*covD(2,2)-2*sxy*covD(3,2));
        se=[sqrt(max(0,sxx*covD(2,2))), ...
            sqrt(max(0,syy*covD(3,3))), ...
            sqrt(max(0,vxy)),sqrt(max(0,vrot))];
        alpha=1-ci;
        try
            crit=tinv(1-alpha/2,dof);
        catch
            q=betaincinv(alpha,dof/2,.5);
            crit=sqrt(dof*(1-q)/q);
        end
        out.lower(t,:)=out.strain(t,:)-crit*se;
        out.upper(t,:)=out.strain(t,:)+crit*se;
    else
        n=numel(ids);samples=nan(nrep,4);
        if method==3
            % Spatial-block bootstrap: resample occupied grid cells.
            % Grid resolution ~sqrt(N/8), at least 2 x 2 cells.
            side=max(2,round(sqrt(n/8)));
            mins=min(X,[],1);span=max(X,[],1)-mins;
            span(span==0)=1;
            cellXY=min(side-1,floor((X-mins)./span*side));
            [~,~,blockID]=unique(cellXY,'rows');
            groups=unique(blockID);ng=numel(groups);
        end
        for k=1:nrep
            if method==2
                take=randi(n,n,1);
            else
                draw=groups(randi(ng,ng,1));
                take=[];
                for j=1:numel(draw)
                    take=[take;find(blockID==draw(j))]; %#ok<AGROW>
                end
            end
            if numel(take)<4,continue;end
            Db=D(take,:);
            if rank(Db)<3,continue;end
            Bb=Db\U(take,:);
            samples(k,:)=[Bb(2,1),Bb(3,2), ...
                .5*(Bb(3,1)+Bb(2,2)),.5*(Bb(3,1)-Bb(2,2))];
        end
        for c=1:4
            out.lower(t,c)=semQuantile(samples(:,c),(1-ci)/2);
            out.upper(t,c)=semQuantile(samples(:,c),1-(1-ci)/2);
        end
    end
end
end
