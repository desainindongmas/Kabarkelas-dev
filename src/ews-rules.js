// G0.6 human-review-only indicators; no student labels and no automated parent sharing.
export function evaluateEarlyWarning({grades=[],attendance=[]},settings={}){
 const minGrades=settings.minGrades??2;
 const threshold=settings.gradeThreshold??70;
 const absentThreshold=settings.absentCount??3;
 if(!Number.isInteger(minGrades)||minGrades<1||!Number.isFinite(threshold)||threshold<0||threshold>100||!Number.isInteger(absentThreshold)||absentThreshold<1) throw new RangeError('Konfigurasi EWS tidak valid');
 const valid=grades.filter(g=>g&&g.finalized===true&&Number.isFinite(g.score)&&Number.isFinite(g.maxScore)&&g.maxScore>0&&g.score>=0&&g.score<=g.maxScore);
 const normalized=valid.map(g=>100*g.score/g.maxScore);
 const absence=attendance.filter(a=>a==='absent').length;
 const items=[];
 if(normalized.length>=minGrades){
   const average=normalized.reduce((a,b)=>a+b,0)/normalized.length;
   if(average<threshold)items.push({code:'academic_review',severity:'review',observed:Math.round(average*100)/100,explanation:'Rata-rata '+normalized.length+' penilaian final di bawah ambang tinjauan'});
 }
 if(absence>=absentThreshold)items.push({code:'attendance_review',severity:'review',observed:absence,explanation:'Ketidakhadiran tercatat mencapai ambang tinjauan'});
 return {status:items.length?'review_suggested':'no_alert',signals:items,gradeSampleSize:normalized.length,attendanceSampleSize:attendance.length,needsHumanReview:true};
}
