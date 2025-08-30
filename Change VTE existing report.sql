DECLARE @StartDate	as Date = '2025-06-01'
DECLARE @EndDate	as Date = '2025-06-30'
;
/*
Changes made:
	- CTE "Dataset": 
			Select & Group By:	
				--,DATEADD(month, DATEDIFF(month, 0, DISCHARGE_DATE_HOSPITAL_PROVIDER_SPELL), 0) AS StartOfMonthDischarged (Commented)
				,DATEADD(month, DATEDIFF(month, 0, START_DATE_TIME_HOSPITAL_PROVIDER_SPELL), 0) AS StartOfMonthAdmitted (Added)

			Where:	
				--and DISCHARGE_DATE_HOSPITAL_PROVIDER_SPELL between @StartDate and @EndDate (Commented)
				and START_DATE_TIME_HOSPITAL_PROVIDER_SPELL between @StartDate and @EndDate (Added)
*/

with vte_risk_assessment as 
			(select distinct encounter_id, FORM_NAME, SECTION_NAME, FIELD_NAME as VTE_RA_Field_Name, FIELD_VALUE as VTE_RA_Field_Value, PERFORMED_DATE_TIME as VTE_RA_Date_Time
			,row_number() over(partition by encounter_id order by performed_date_time asc) vte_risk_assessment_order
			from reporting.CERNER_FORM
			where FORM_NAME = 'VTE Risk Assessment'
						and SECTION_NAME in ('Patient Group','Mobility')
						and FIELD_NAME = 'VTE Override'
						and FIELD_VALUE = 'No Override'
			)		

,vte_risk as
			(select distinct encounter_id, FORM_NAME, SECTION_NAME, FIELD_NAME as VTE_Risk_Field_Name, FIELD_VALUE as VTE_Risk_Field_Value from reporting.CERNER_FORM where FIELD_NAME = 'VTE Risk'
			)

-- bleeding risk exclusions added 
, bleeding_risk_exclusions as (
			select distinct encounter_id, FORM_NAME, SECTION_NAME, FIELD_NAME as Bleed_Risk_Field_Name, FIELD_VALUE as Bleed_Risk_Field_Value from reporting.CERNER_FORM where form_name like '%vte%' and FIELD_NAME = 'Bleeding Risk' and FIELD_VALUE = 'Yes'
			)

, vte_prescription as 
			(select distinct encounter_id, FORM_NAME, SECTION_NAME, FIELD_NAME as VTE_Prescription_Field_Name, FIELD_VALUE as VTE_Prescription_Field_Value, case when FIELD_VALUE = 'yes' then PERFORMED_DATE_TIME end as VTE_Prescription_Date_Time
			from reporting.CERNER_FORM
			where FORM_NAME = 'VTE Risk Assessment'
						and SECTION_NAME = 'Prescribing'
			)

, anticoagulant_dose_check as 
			(select distinct ENCOUNTER_ID, form_name, SECTION_NAME,FIELD_NAME as anticoag_field_name, FIELD_VALUE as anticoag_field_value from reporting.CERNER_FORM
			where FORM_NAME like '%anticoagulant dose check' or FORM_NAME like '%anticoagulant review%'
			)

, thromboprophylaxis as 
			(select distinct *, try_convert(datetime, left(substring(clinical_display_line, patindex('%[0-9][0-9]/[A-Z][a-z][a-z]/[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]%', CLINICAL_DISPLAY_LINE), 103),20)) dose_date_time
			from reporting.orders where ORDER_CATALOG_DESCRIPTION like '%daltep%'
			--or ORDER_CATALOG_DESCRIPTION like '%apixaban%' -- excluded
			--or ORDER_CATALOG_DESCRIPTION like '%warfarin%' -- excluded
			-- or ORDER_CATALOG_DESCRIPTION like '%rivaroxaban%' -- excluded
			-- or ORDER_CATALOG_DESCRIPTION like '%edoxaban%' -- excluded
			-- or ORDER_CATALOG_DESCRIPTION like '%dabigatran%' -- excluded
				or ORDER_CATALOG_DESCRIPTION like '%Fondaparinux%' -- included
				or ORDER_CATALOG_DESCRIPTION = 'Heparin' -- included
			)

, dataset as (
			select distinct hps.SOURCE_ID
			,hps.local_patient_identifier as hosp_number
			,PERSON_FULL_NAME
			,hps.START_DATE_TIME_HOSPITAL_PROVIDER_SPELL Admission_Date_Time
			,hps.DISCHARGE_DATE_TIME_HOSPITAL_PROVIDER_SPELL Discharge_Date_Time
			, hps.Decided_To_Admit_Date_Time
			, case when vte_risk_assessment.VTE_RA_Field_Name = 'VTE Override'
						and vte_risk_assessment.vte_ra_field_Value = 'No Override'
						then 'VTE Risk Assessment Done' 
						else 'VTE Risk Assessment Not Done' end as VTE_Risk_Assessment_Done
			, case when vte_risk.VTE_Risk_Field_Name  = 'VTE Risk' and VTE_Risk_Field_Value = 'Yes' then 'VTE Risk'
				   when vte_risk.VTE_Risk_Field_Name  = 'VTE Risk' and VTE_Risk_Field_Value = 'No' then 'No VTE Risk'
				   end as VTE_Risk_Status
			, case when vte_risk_assessment.FORM_NAME = 'VTE Risk Assessment'
						and vte_risk_assessment.SECTION_NAME in ('Patient Group','Mobility')
						and vte_risk_assessment.VTE_RA_Field_Name = 'VTE Override'
						and vte_risk_assessment.VTE_RA_Field_Value = 'No Override'
						then vte_risk_assessment.VTE_RA_Date_Time
						end as VTE_Risk_Assessment_Date_Time
			, case when vte_prescription.FORM_NAME = 'VTE Risk Assessment'
						and vte_prescription.SECTION_NAME = 'Prescribing'
						and vte_prescription.VTE_Prescription_Field_Name = 'VTE Reason Prophylaxis Not Prescribed' then 'VTE Prophylaxis Not Prescribed'
				   when vte_prescription.FORM_NAME = 'VTE Risk Assessment'
						and vte_prescription.SECTION_NAME = 'Prescribing'
						and vte_prescription.VTE_Prescription_Field_Name = 'VTE Prophylaxis Prescribed'
						and vte_prescription.VTE_Prescription_Field_Value = 'No' then 'VTE Prophylaxis Not Prescribed'
				   when vte_prescription.FORM_NAME = 'VTE Risk Assessment'
						and vte_prescription.SECTION_NAME = 'Prescribing'
						and vte_prescription.VTE_Prescription_Field_Name = 'VTE Prophylaxis Prescribed'
						and vte_prescription.VTE_Prescription_Field_Value = 'Yes' then 'VTE Prophylaxis Prescribed'
				   end as VTE_Prophylaxis_Prescription
			, case when vte_prescription.FORM_NAME = 'VTE Risk Assessment'
						and vte_prescription.SECTION_NAME = 'Prescribing'
						and vte_prescription.VTE_Prescription_Field_Name = 'VTE Prophylaxis Prescribed'
						and vte_prescription.VTE_Prescription_Field_Value = 'Yes' then VTE_Prescription_Date_Time
						end as VTE_Prophylaxis_Prescription_Date_Time
			, string_agg(concat(anticoag_field_name,': ',anticoag_field_value),', ') Anticoag_Notes
			,thromboprophylaxis.ORDER_CATALOG_DESCRIPTION
			,thromboprophylaxis.CLINICAL_DISPLAY_LINE
			--,concat(thromboprophylaxis.STRENGTH_DOSE, ' ', thromboprophylaxis.STRENGTH_DOSE_UNIT) Dose
			, case when dose_date_time is not null then
			ROW_NUMBER() over (partition by thromboprophylaxis.encounter_id 
			order by dose_date_time asc) else 0 end as dose_order
			, case when dose_date_time is not null then
			ROW_NUMBER() over (partition by thromboprophylaxis.encounter_id 
			order by dose_date_time desc)
			else 0 end as number_of_recorded_doses -- only use this name if you're looking at the first dose only. Otherwise call it reverse_dose_order 
			, case when dose_date_time is not null then dose_date_time else VTE_Prescription_Date_Time end as thromboprophylaxis_dose_date_time
			, case when ROW_NUMBER() over (partition by thromboprophylaxis.encounter_id 
					order by dose_date_time asc) = '1' 
					then datediff(hh,hps.START_DATE_TIME_HOSPITAL_PROVIDER_SPELL,dose_date_time)
					end as Hours_between_Admission_and_Dose
			, case when datediff(hh,hps.START_DATE_TIME_HOSPITAL_PROVIDER_SPELL,dose_date_time) <= '14'  
					and ROW_NUMBER() over (partition by thromboprophylaxis.encounter_id 
					order by dose_date_time asc) = '1' then 0 -- 0 is a non-breach i.e. was administered within 14 hours
				   when datediff(hh,hps.START_DATE_TIME_HOSPITAL_PROVIDER_SPELL,dose_date_time) > '14' 
					and ROW_NUMBER() over (partition by thromboprophylaxis.encounter_id 
					order by dose_date_time asc) = '1' then 1 -- 1 is a breach i.e. was not administered within 14 hours
				   else 0
				   end as '14 Hour Breach Status'
			,patient.PERSON_BIRTH_DATE_TIME
			,ward.ward_desc1 Ward_At_Admission
			,ward.LAST_REAL_WARD_LOCAL Ward_Current_Discharge
			--,DATEADD(month, DATEDIFF(month, 0, DISCHARGE_DATE_HOSPITAL_PROVIDER_SPELL), 0) AS StartOfMonthDischarged
			,DATEADD(month, DATEDIFF(month, 0, START_DATE_TIME_HOSPITAL_PROVIDER_SPELL), 0) AS StartOfMonthAdmitted


			from reporting.HOSPITAL_PROVIDER_SPELL hps
			left join thromboprophylaxis
			on hps.SOURCE_ID=thromboprophylaxis.ENCOUNTER_ID
			left join vte_risk_assessment
			on hps.SOURCE_ID=vte_risk_assessment.ENCOUNTER_ID
			left join vte_risk
			on hps.SOURCE_ID=vte_risk.ENCOUNTER_ID
			left join vte_prescription
			on hps.SOURCE_ID=vte_prescription.ENCOUNTER_ID
			left join anticoagulant_dose_check
			on hps.SOURCE_ID=anticoagulant_dose_check.ENCOUNTER_ID
			left join reporting.patient 
			on hps.LOCAL_PATIENT_IDENTIFIER=PATIENT.LOCAL_PATIENT_IDENTIFIER
			left join reporting.HOSPITAL_PROVIDER_SPELL_WARD_STAY_FLAT ward 
			on hps.SOURCE_ID=ward.HOSPITAL_PROVIDER_SPELL_SOURCE_ID
			left join bleeding_risk_exclusions
			on hps.SOURCE_ID=bleeding_risk_exclusions.ENCOUNTER_ID

			where 1=1
			--and DISCHARGE_DATE_HOSPITAL_PROVIDER_SPELL between @StartDate and @EndDate
			and START_DATE_TIME_HOSPITAL_PROVIDER_SPELL between @StartDate and @EndDate
			and (datediff(hh,start_date_hospital_provider_spell,discharge_date_hospital_provider_spell) > '6' or vte_risk.VTE_Risk_Field_Name  = 'VTE Risk' and VTE_Risk_Field_Value = 'Yes')
			and (vte_risk_assessment_order = '1' or VTE_RA_Date_Time is null)
			and AGE_AT_ADMISSION >= '16'
			and bleeding_risk_exclusions.Bleed_Risk_Field_Value is null

			group by hps.SOURCE_ID
			,hps.local_patient_identifier
			,PERSON_FULL_NAME
			,hps.START_DATE_TIME_HOSPITAL_PROVIDER_SPELL
			,hps.DISCHARGE_DATE_TIME_HOSPITAL_PROVIDER_SPELL
			,thromboprophylaxis.ENCOUNTER_ID
			, hps.Decided_To_Admit_Date_Time
			, case when vte_risk_assessment.VTE_RA_Field_Name = 'VTE Override'
						and vte_risk_assessment.vte_ra_field_Value = 'No Override'
						then 'VTE Risk Assessment Done' 
						else 'VTE Risk Assessment Not Done' end
			, case when vte_risk.VTE_Risk_Field_Name  = 'VTE Risk' and VTE_Risk_Field_Value = 'Yes' then 'VTE Risk'
				   when vte_risk.VTE_Risk_Field_Name  = 'VTE Risk' and VTE_Risk_Field_Value = 'No' then 'No VTE Risk'
				   end
			, case when vte_risk_assessment.FORM_NAME = 'VTE Risk Assessment'
						and vte_risk_assessment.SECTION_NAME in ('Patient Group','Mobility')
						and vte_risk_assessment.VTE_RA_Field_Name = 'VTE Override'
						and vte_risk_assessment.VTE_RA_Field_Value = 'No Override'
						then vte_risk_assessment.VTE_RA_Date_Time
						end
			, case when vte_prescription.FORM_NAME = 'VTE Risk Assessment'
						and vte_prescription.SECTION_NAME = 'Prescribing'
						and vte_prescription.VTE_Prescription_Field_Name = 'VTE Reason Prophylaxis Not Prescribed' then 'VTE Prophylaxis Not Prescribed'
				   when vte_prescription.FORM_NAME = 'VTE Risk Assessment'
						and vte_prescription.SECTION_NAME = 'Prescribing'
						and vte_prescription.VTE_Prescription_Field_Name = 'VTE Prophylaxis Prescribed'
						and vte_prescription.VTE_Prescription_Field_Value = 'No' then 'VTE Prophylaxis Not Prescribed'
				   when vte_prescription.FORM_NAME = 'VTE Risk Assessment'
						and vte_prescription.SECTION_NAME = 'Prescribing'
						and vte_prescription.VTE_Prescription_Field_Name = 'VTE Prophylaxis Prescribed'
						and vte_prescription.VTE_Prescription_Field_Value = 'Yes' then 'VTE Prophylaxis Prescribed'
				   end
			, case when vte_prescription.FORM_NAME = 'VTE Risk Assessment'
						and vte_prescription.SECTION_NAME = 'Prescribing'
						and vte_prescription.VTE_Prescription_Field_Name = 'VTE Prophylaxis Prescribed'
						and vte_prescription.VTE_Prescription_Field_Value = 'Yes' then VTE_Prescription_Date_Time
						end
			,thromboprophylaxis.ORDER_CATALOG_DESCRIPTION
			,thromboprophylaxis.CLINICAL_DISPLAY_LINE
			--,concat(thromboprophylaxis.STRENGTH_DOSE, ' ', thromboprophylaxis.STRENGTH_DOSE_UNIT) Dose
			, case when dose_date_time is not null then dose_date_time else VTE_Prescription_Date_Time end
			, dose_date_time
			, datediff(hh,hps.START_DATE_TIME_HOSPITAL_PROVIDER_SPELL,dose_date_time) 
			, case  when datediff(hh,hps.START_DATE_TIME_HOSPITAL_PROVIDER_SPELL,thromboprophylaxis.ORDER_DATE_TIME) <= '14' then '1'
					when datediff(hh,hps.START_DATE_TIME_HOSPITAL_PROVIDER_SPELL,thromboprophylaxis.ORDER_DATE_TIME) > '14' then '0'
					end
			,patient.PERSON_BIRTH_DATE_TIME
			,ward.ward_desc1 
			,ward.LAST_REAL_WARD_LOCAL 
			--,DATEADD(month, DATEDIFF(month, 0, DISCHARGE_DATE_HOSPITAL_PROVIDER_SPELL), 0)
			,DATEADD(month, DATEDIFF(month, 0, START_DATE_TIME_HOSPITAL_PROVIDER_SPELL), 0)
			)

select *
, case when anticoag_notes = ': ' or anticoag_notes  like '%: , : %' then 'No Notes' else Anticoag_Notes end as Anticoag_Notes_2

from dataset

where 1=1
AND dose_order in ('1','0') -- or reverse_dose_order = '1'
AND Ward_Current_Discharge NOT LIKE '%RS ED%'
AND Ward_Current_Discharge <> 'RS Emergency Department'
AND Ward_Current_Discharge NOT LIKE '%RS AEC%'
AND Ward_Current_Discharge NOT LIKE '%RS AECU%'
AND Ward_Current_Discharge NOT LIKE '%RS CDU%'
AND Ward_Current_Discharge NOT LIKE '%RS Mortuary%'
AND Ward_Current_Discharge NOT LIKE '%RS Frailty%'
AND Ward_Current_Discharge NOT LIKE '%RS Delivery%'
AND Ward_Current_Discharge NOT LIKE '%RS Maternity%'
AND Ward_Current_Discharge NOT LIKE '%RS Cardiac%'
AND Ward_Current_Discharge NOT LIKE '%RS Main Theatre%'
AND Ward_Current_Discharge NOT LIKE '%RS Endo Theatre%'
AND Ward_Current_Discharge NOT LIKE '%RS%Theatre%'
AND Ward_Current_Discharge NOT LIKE '%RS CHILWORTH%'--exclusion
AND Ward_Current_Discharge NOT LIKE '%RS MAX%FAC%'--exclusion
AND Ward_Current_Discharge NOT LIKE '%RS HASCOMBE PAU%'--exclusion  -- we want hascombe but only patients that are over 16 
AND Ward_Current_Discharge NOT LIKE '%RS MIDWIFE%'--exclusion
AND Ward_Current_Discharge NOT LIKE '%RE%AEC%'--exclusion
AND Ward_Current_Discharge NOT LIKE '%SDEC%'--exclusion

order by SOURCE_ID, thromboprophylaxis_dose_date_time