{{ config(
     enabled = the_tuva_project.tuva_boolean_var('claims_enabled', false)
   )
}}

with first_claim as (
    select *
    from {{ ref('emergency_department__generate_encounter_id') }}
    where encounter_claim_number = 1
)

, join_first_claim_dates as (
    select f.*
    , dat.encounter_end_date
    , dat.encounter_start_date
    from first_claim as f
    inner join {{ ref('emergency_department__start_end_dates') }} as dat on f.encounter_id = dat.encounter_id
)

/* institutional emergency department claims already form their own encounters,
   so they are never rolled up into another emergency department encounter */
, emergency_department_claims as (
    select distinct
          claim_id
        , patient_data_source_id
    from {{ ref('emergency_department__generate_encounter_id') }}
)


-- ensuring each claim is only attributed to one encounter with claim_attribution_number
, inst_and_prof as (
select dat.encounter_id
, dat.encounter_start_date
, dat.encounter_end_date
, dat.original_anchor_claim
, prof.claim_id
, prof.claim_line_number
, prof.data_source
from {{ ref('encounters__stg_medical_claim') }} as med
inner join {{ ref('encounters__stg_professional') }} as prof on med.claim_line_id = prof.claim_line_id
and med.data_source = prof.data_source
inner join join_first_claim_dates as dat on med.patient_data_source_id = dat.patient_data_source_id
and med.start_date between dat.encounter_start_date and dat.encounter_end_date

union all

select dat.encounter_id
, dat.encounter_start_date
, dat.encounter_end_date
, dat.original_anchor_claim
, med.claim_id
, med.claim_line_number
, med.data_source
from {{ ref('encounters__stg_medical_claim') }} as med
inner join {{ ref('encounters__stg_outpatient_institutional') }} as inst on med.claim_id = inst.claim_id
and med.data_source = inst.data_source
inner join join_first_claim_dates as dat on med.patient_data_source_id = dat.patient_data_source_id
and med.start_date between dat.encounter_start_date and dat.encounter_end_date
left outer join emergency_department_claims as ed on med.claim_id = ed.claim_id
and med.patient_data_source_id = ed.patient_data_source_id
where ed.claim_id is null
)

select distinct encounter_id
, encounter_start_date
, encounter_end_date
, claim_id
, claim_line_number
, data_source
, row_number() over (partition by claim_id, claim_line_number, data_source
order by original_anchor_claim, encounter_id) as claim_attribution_number
from inst_and_prof
