USE [Fanavaran221-TestAnsari]
GO
/****** Object:  StoredProcedure [dbo].[spMissionUserSel_Clean]    Script Date: 6/24/2025 8:53:32 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER procedure [per].[spMissionUserSel] @EmpIdRef INT,
@StartDate VARCHAR(10)='',
@EndDate VARCHAR(10)=''  ,@CompanyId INT =-1 
As

declare @maxDistance as int  , @fromDate varchar(10) , @toDate varchar(10) 

--set @empId = 936
set @maxDistance=300
-- بدست اوردن روز قبل و روز بعد بازه تاریخی 
set @fromDate = (select [per].[CalcYesterdayShamsi](@StartDate))
set @toDate  = ( select [per].[CalcTomorrowShamsi]( @EndDate ))
-- استخراج فرم کارها برای این تاریخ
create table #myFormWork(
	Id int,
	EmpIdRef varchar(10),
	Stime varchar(10),
	EndTime varchar(10),
	EzafeKAr varchar(10),
	PostFrom int,
	PostTo int,
	Dsc varchar(1000),
	FormDate varchar(10),
	Distance int,
	prjCode varchar(20),
	Tomorrow varchar(10),
	YesterDay varchar(10),
	FromPost  varchar(40),
	ToPost  varchar(40),
	Mission int,
	IsMission bit,
	MisCode tinyint
)
insert into   #myFormWork(Id , EmpIdRef , Stime , EndTime , EzafeKAr , Dsc , FormDate , Distance , prjCode , FromPost , ToPost  , Tomorrow , YesterDay , Mission , IsMission , PostFrom , PostTo)
select  w.Srl , w.Srl_Pm_Ashkhas  
,CASE WHEN LEN(RIGHT(BeginWorkSat, CHARINDEX(':', REVERSE(BeginWorkSat)) - 1)) = 1 THEN LEFT(BeginWorkSat, CHARINDEX(':', BeginWorkSat)) + '0' + RIGHT(BeginWorkSat, CHARINDEX(':', REVERSE(BeginWorkSat)) - 1) ELSE BeginWorkSat END AS BeginWorkSat
,CASE WHEN LEN(RIGHT(EndWorkSat, CHARINDEX(':', REVERSE(EndWorkSat)) - 1)) = 1 THEN LEFT(EndWorkSat, CHARINDEX(':', EndWorkSat)) + '0' + RIGHT(EndWorkSat, CHARINDEX(':', REVERSE(EndWorkSat)) - 1) ELSE EndWorkSat END AS EndWorkSat
,CASE WHEN LEN(RIGHT(EzafeKAr, CHARINDEX(':', REVERSE(EzafeKAr)) - 1)) = 1 THEN LEFT(EzafeKAr, CHARINDEX(':', EzafeKAr)) + '0' + RIGHT(EzafeKAr, CHARINDEX(':', REVERSE(EzafeKAr)) - 1) ELSE EzafeKAr END AS EzafeKAr
, w.WorkFormDis    , w.WorkFormTarikh  , d.Distance , w.Srl_HazineCode   
 , p.Name as FromPost , p2.Name as ToPost ,   (select [per].[CalcTomorrowShamsi](w.WorkFormTarikh)) as Tomorrow ,(select [per].[CalcYesterdayShamsi](w.WorkFormTarikh)) as YesterDay , 1 , case when d.distance >= 50 then 1 else 0 end,
 w.Srl_Pm_Post_From , w.Srl_Pm_Post_To
from per.WorkForm as w
join per.pm_Distance as d
on d.Srl_Post1 = w.Srl_Pm_Post_From and d.Srl_Post2 = w.Srl_Pm_Post_To
join  per.Pm_post as p
on p.Srl = w.Srl_Pm_Post_To
join  per.Pm_post as p2
on p2.Srl = w.Srl_Pm_Post_From
where  w.WorkFormTarikh between @fromDate and @toDate and (Srl_Pm_Ashkhas=@EmpIdRef OR @EmpIdRef=-1)
order by WorkFormTarikh

-- بدست آوردن روزهایی که فرم کار پر کرده به همراه ماکس فاصله و مین ساعت شروع و تاریخ فردا و دیروز
;WITH AggregatedData AS
(
    SELECT 
        EmpIdRef, 
        FormDate,
        MAX(Distance) AS MaxDistance,
        MIN(Distance) AS MinDistance,
        MAX(CAST(REPLACE(EndTime, ':','') AS INT)) AS EndTimeMax,
        MIN(CAST(REPLACE(STime, ':','') AS INT)) AS STimeMin,
        MAX(YesterDay) AS YesterDay,  -- Optional: pick latest or earliest depending on logic
        MAX(Tomorrow) AS Tomorrow,
        MAX(Dsc) AS Dsc,
        MAX(PostFrom) AS PostFrom,
        MAX(PostTo) AS PostTo,
        MAX(prjCode) AS prjCode,
        MAX(FromPost) AS FromPost,
        MAX(ToPost) AS ToPost,
        MAX(MisCode) AS MisCode

    FROM #myFormWork 
    WHERE FormDate > @StartDate
    GROUP BY EmpIdRef, FormDate
)

SELECT  
    EmpIdRef,
    FormDate,
    YesterDay,
    Tomorrow,
    MaxDistance,
    MinDistance,
    EndTimeMax,
    STimeMin,
    PostFrom,
    PostTo,
    Dsc,
    prjCode,
    FromPost,
    ToPost,
    0 AS IsMission,
    MisCode,
    1.0 AS SumMission
INTO #DistanceTbl
FROM AggregatedData
ORDER BY FormDate;

update #DistanceTbl set IsMission = 1 where maxDistance >= 50
delete from #DistanceTbl where MaxDistance <49


-- ایجاد جدول بدست امده برای روزهای بعداز فرم کار 

select  
	dt.EmpIdRef ,
	dt.maxDistance ,
	dt.FormDate as YesterDay , 
	dt.Tomorrow as FormDate , 
	(select per.CalcTomorrowShamsi(dt.Tomorrow)) as Tomorrow , 
	dt.EndTimeMax , 
	dt.STimeMin , 
	dt.PostFrom , 
	dt.PostTo , 
	dt.Dsc , 
	dt.PrjCode , 
	dt.FromPost , 
	dt.ToPost , 
	dt.IsMission , 
	dt.MisCode , 

case when dt.maxDistance>=@maxDistance and ad.ArrivedDate is not null and ad.ArrivedDate<> @toDate then 1 
	when (dt.maxDistance>=140 and dt.maxDistance<@maxDistance and ad.ArrivedDate is not null and ad.ArrivedDate<> @toDate) then 0.5 else 0 end as TMission  into #TomorrowTbl
from  #DistanceTbl as dt
left join per.FormWorkArriveDetail as ad
on ad.ArrivedDate=dt.Tomorrow and ad.EmpIdRef = dt.EmpIdRef

delete from #TomorrowTbl where TMission <= 0


select   dt.EmpIdRef ,  dt.maxDistance , (select per.CalcYesterdayShamsi(dt.YesterDay) ) as YesterDay , dt.YesterDay as FormDate   , dt.FormDate as Tomorrow  , dt.EndTimeMax , dt.STimeMin, dt.PostFrom , dt.PostTo, dt.Dsc , dt.PrjCode , dt.FromPost , dt.ToPost , 
  dt.IsMission ,dt.MisCode   , 0.5 as YMission   into #YesterDayTbl
from  #DistanceTbl as dt
left join (select * from #DistanceTbl where maxDistance >=50) as dt2
on dt.EmpIdRef = dt2.EmpIdRef and dt.YesterDay = dt2.FormDate
where dt2.FormDate is null and  dt.STimeMin<=800 and dt.maxDistance>=140 and dt.FormDate > @StartDate






delete from #TomorrowTbl where TMission <= 0



-- برای روز های پاداش به بعد و قبل، باید ببینیم اگر در یک روز مشخص، هم پاداش روز قبل دارد هم پاداش روز بعد،م
-- مجموع مقدار ماموریت پاداشی را بر اساس فرم کاری که فاصله اش بیشتر است در نظر میگیریم.
-- بیشترین مقدار پاداش در یک روز کلا 1 است 
-- این مقادیر استثنا را در جدول زیر نگهداری مکینم
select
y.EmpIdRef ,
case when y.maxDistance > t.maxDistance then y.maxDistance else t.maxDistance end as maxDistance,
y.YesterDay ,
y.FormDate , 
y.Tomorrow , 
case when y.maxDistance > t.maxDistance then y.EndTimeMax else t.EndTimeMax end as EndTimeMax,
case when y.maxDistance > t.maxDistance then y.STimeMin else t.STimeMin end as STimeMin,
case when y.maxDistance > t.maxDistance then y.PostFrom else t.PostFrom end as PostFrom,
case when y.maxDistance > t.maxDistance then y.PostTo else t.PostTo end as PostTo,
case when y.maxDistance > t.maxDistance then y.Dsc else t.Dsc end as Dsc,
case when y.maxDistance > t.maxDistance then y.prjCode else t.prjCode end as prjCode,
case when y.maxDistance > t.maxDistance then y.FromPost else t.FromPost end as FromPost,
case when y.maxDistance > t.maxDistance then y.ToPost else t.ToPost end as ToPost,
1 as IsMission,
t.MisCode ,
case when (t.TMission + y.YMission) >= 1 then 1 else (t.TMission + y.YMission) end as TMission
into #integrateMPerDay
from #YesterDayTbl as y
left join #TomorrowTbl as t
on y.FormDate=t.FormDate and y.EmpIdRef = t.EmpIdRef
where t.TMission is not null

-- حلا روزهایی که مجموع شان را حساب کرده ایم را در جدول روزهای بعد و روزهای قبل حذف میکنیم
-- یعنی اشتراکات را حساب کردیم و الان باید حرف کنیم
--  میتوانستیم با جوین هم پیدا کنیم
delete from #YesterDayTbl where FormDate in (select FormDate from #integrateMPerDay)
delete from #TomorrowTbl where FormDate in (select FormDate from #integrateMPerDay)


--select * from #DistanceTbl
--select * from #integrateMPerDay
--select * from #YesterDayTbl
--select * from #TomorrowTbl



--  پس ما الان اشتراکات را در جدول های روز بعد و روز قبل حذف کردیم


--الان باید دیتاهای هر سه جدول یعنی جدول دیروز و فردا و اشتراکات را داخل جدول اصلی مان اینسرت کنیم

insert into #DistanceTbl (EmpIdRef , maxDistance , YesterDay , FormDate , Tomorrow , EndTimeMax , STimeMin , PostFrom , PostTo , Dsc , prjCode , FromPost , ToPost , IsMission , MisCode , SumMission ) select * from #integrateMPerDay
insert into #DistanceTbl (EmpIdRef , maxDistance , YesterDay , FormDate , Tomorrow , EndTimeMax , STimeMin , PostFrom , PostTo , Dsc , prjCode , FromPost , ToPost , IsMission , MisCode , SumMission ) select * from #YesterDayTbl
insert into #DistanceTbl (EmpIdRef , maxDistance , YesterDay , FormDate , Tomorrow , EndTimeMax , STimeMin , PostFrom , PostTo , Dsc , prjCode , FromPost , ToPost , IsMission , MisCode , SumMission ) select * from #TomorrowTbl





--select * from #DistanceTbl

-- update MisCode in #myFormWork
update #DistanceTbl set MisCode = (case when maxDistance >= 50 and maxDistance < 140 then 1  when maxDistance >= 140 and maxDistance<300 then 2 when maxDistance>=300 then 4 else 0 end);


SELECT DISTINCT   Srl_Pm_Ashkhas,WorkFormTarikh ,pf.ostan AS FOstan , pf.Ostan,pt.ostan  AS TOstan, CAST('' AS VARCHAR(200) ) PostFrom,CAST('' AS VARCHAR(200) ) PostTo  INTO #m  
FROM per.WorkForm wf JOIN  
  per.Pm_PostOstanDetailes as pf   on pf.Srl = wf.Srl_Pm_Post_from  JOIN   
  per.Pm_PostOstanDetailes as pt   on pt.Srl = wf.Srl_Pm_Post_to
WHERE wf.WorkFormTarikh   between @fromDate and @toDate  AND ( pt.Srl_Pm_Ostan IN (4,5)  OR pf.Srl_Pm_Ostan IN (4,5))    


UPDATE m SET  postFrom =w.Srl_Pm_Post_From,PostTo=w.Srl_Pm_Post_To  FROM #m m 
JOIN per.WorkForm w 
ON w.WorkFormTarikh =m.WorkFormTarikh AND w.Srl_Pm_Ashkhas = m.Srl_Pm_Ashkhas


select 
 0 as Id , 
 p.Id as EmpIdRef,
 p.PersonalCode as TfIdRef , 
 p.Name , 
 p.Family,
 d.SumMission as MTime,
 d.prjCode ,
 d.FormDate  as SDate,
 d.FormDate as EDate, 
 u.Id as UserId,
 '' as MTimeDesc,
 '' as Vehicle1Title ,
 '' as Vehicle2Title,
 2 as Vehicle1,
 2 as Vehicle2,
 '' as MissionSubj,
 '' as MissionReport,
 convert(varchar(5) , d.STimeMin) as TimeIn,

 convert(varchar(5) , d.EndTimeMax)as TimeOut,
 0 as Year , 
 0 as Mnt , 
 0 as AppDate ,
 0 as KDate ,
 0 as KUser,
 u.Title as GpName,
 1 as approve,
 ISNULL(i.CompanyId , 8) as CompanyId,
 c.Name as CompanyName,
 0 as CostPrice,
 0 as LunchPrice,
 d.MisCode ,
 ISNULL(m.TOstan , 'خراسان رضوی')  as MisCodeTitle,
CASE WHEN d.MisCode= 1 THEN p2.MisPrice1 
		 WHEN d.MisCode= 2 THEN p2.MisPrice2
		 WHEN d.MisCode= 3 THEN p2.MisPrice3 
		 WHEN d.MisCode= 4 THEN p2.MisPrice4 
    END       AS PerPrice,
	0 as City,
	0 as State,
	'باید مبدا و مقصد باشد' as MisPlace,
	d.maxDistance as Distance
from #DistanceTbl as d
left join per.Employee as p
on d.EmpIdRef = p.Id
left join pcs.Users as us
on us.EmpIdRef = d.EmpIdRef
left join per.PerInfo as i
on i.EmpIdRef = d.EmpIdRef
left join per.Units as u
on u.Id = i.UnitId
LEFT JOIN per.PerInfo p2   ON d.EmpIdRef = p2.EmpIdRef 

LEFT JOIN per.MissionRatePrice mrp 
ON d.EmpIdRef=mrp.EmpIdRef 
left join per.PerCompany as c
on i.CompanyId = c.Id
LEFT JOIN  #m as m 
ON d.EmpIdRef=m.Srl_Pm_Ashkhas  AND d.FormDate COLLATE SQL_Latin1_General_CP1256_CI_AS = m.WorkFormTarikh COLLATE SQL_Latin1_General_CP1256_CI_AS
where p.Id is not null

UNION ALL 


SELECT  M.Id,
M.EmpIdRef,
e.TfIdRef, 
e.Name,
e.Family,
M.MTime, 
M.PrjCode, 
M.SDate ,
M.EDate ,
 M.Userid,
 M.MTimeDesc,
        CASE WHEN M.Vehicle1=0 THEN 'شخصي' ELSE 'شرکتي' END Vehicle1Title,
        CASE WHEN M.Vehicle2=0 THEN 'شخصي' ELSE 'شرکتي' END Vehicle2Title,   
		M.Vehicle1,
		M.Vehicle2  ,
        M.MissionSubj, M.MissionReport, M.TimeIn, M.[TimeOut],
		isnull(m.[Year] , 0) as Year  ,
        ISNULL(m.Mnt , 0) as Mnt ,
		CAST(m.[Year] AS VARCHAR(10))+'/'+CAST(m.Mnt AS VARCHAR(10))  AS AppDate ,
            M.KDate, M.KUser, ISNULL(u.Title , '')  AS GpName ,
  m.approve ,e.CompanyId,c.Name AS CompanyName  ,
 M.CostPrice,
 CAST( 0 AS BIGINT) AS LunchPrice ,
 M.MisCode  ,
    CASE WHEN M.MisCode=3  THEN 'خارج استان خراسان بزرگ'   
		 WHEN M.MisCode=4  THEN 'خراسان جنوبی و شمالی'   
		 ELSE 'داخل استان'
	END      MisCodeTitle ,
    CASE WHEN m.miscode= 1 THEN p.MisPrice1 
		 WHEN m.miscode= 2 THEN p.MisPrice2
		 WHEN m.miscode= 3 THEN p.MisPrice3 
		 WHEN m.miscode= 4 THEN p.MisPrice4 
    END       AS PerPrice , m.City, m.[State] ,c3.CName+ '-' +  c2.CName   AS MisPlace ,0 AS Distance 
  FROM per.Mission m 
  JOIN per.Employee e ON m.EmpIdRef=e.Id LEFT JOIN
  per.PerInfo p   ON p.EmpIdRef =m.EmpIdRef
  LEFT JOIN per.MissionRatePrice mrp  ON m.EmpIdRef=mrp.EmpIdRef 
  LEFT JOIN pcs.PerCompany c ON c.Id=e.CompanyId
  LEFT JOIN  per.units u ON  u.Id =p.UnitId  LEFT JOIN 
  cnt.City c2  ON c2.CId = m.city  LEFT JOIN 
  cnt.City c3  ON c3.CId = m.[State]
WHERE (e.Id=@EmpIdRef OR @EmpIdRef=-1)  AND (c.Id=@CompanyId OR @CompanyId=-1) and (m.SDate between @StartDate and @EndDate) 
order by EmpIdRef , SDate 




