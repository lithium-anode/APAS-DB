use `apas_db`;

delimiter //

-- =================================================================
-- function 1: fn_ismanagerof (security check)
-- checks if p_manager_id is the direct manager of p_employee_id
-- =================================================================
create function `fn_ismanagerof`(
    p_manager_id int,
    p_employee_id int
) 
returns boolean
reads sql data
begin
    declare v_actual_manager_id int;

    select `manager_id` into v_actual_manager_id
    from `employees`
    where `employee_id` = p_employee_id;

    if v_actual_manager_id = p_manager_id then
        return true;
    else
        return false;
    end if;
end//

-- =================================================================
-- function 2: fn_getemployeeweightedscore (calculation engine)
-- calculates the final weighted score for an employee in a cycle.
-- assumes rating is on a 1-5 scale and weightage is a percentage.
-- logic: sum( (rating / 5) * weightage )
-- =================================================================
create function `fn_getemployeeweightedscore`(
    p_employee_id int,
    p_cycle_id int
) 
returns decimal(5,2)
reads sql data
begin
    declare v_total_score decimal(5,2) default 0.00;

    select sum((mr.rating / 5) * g.goal_weightage)
    into v_total_score
    from `goals` g
    join `manager_reviews` mr on g.goal_id = mr.goal_id
    where 
        g.employee_id = p_employee_id
        and g.cycle_id = p_cycle_id
        and g.goal_status in ('approved', 'completed') -- only count rated goals
        and mr.rating is not null;

    -- if no rated goals are found, v_total_score will be null.
    -- we use coalesce to return 0.00 in that case.
    return coalesce(v_total_score, 0.00);
end//

-- =================================================================
-- function 3: fn_getappraisalprogress (derived status)
-- derives the current step of an employee in the appraisal process.
-- =================================================================
create function `fn_getappraisalprogress`(
    p_employee_id int,
    p_cycle_id int
) 
returns varchar(100)
reads sql data
begin
    declare v_goal_count int default 0;
    declare v_pending_goals int default 0;
    declare v_appraisal_count int default 0;
    declare v_review_count int default 0;
    declare v_final_rating int default 0;

    -- 1. check if goals are set
    select count(*) 
    into v_goal_count 
    from `goals` 
    where `employee_id` = p_employee_id and `cycle_id` = p_cycle_id;
    
    if v_goal_count = 0 then 
        return '1. awaiting goal setting'; 
    end if;

    -- 2. check if all goals are approved
    select count(*) 
    into v_pending_goals 
    from `goals` 
    where `employee_id` = p_employee_id 
      and `cycle_id` = p_cycle_id 
      and `goal_status` = 'pending_approval';
      
    if v_pending_goals > 0 then 
        return '2. awaiting manager goal approval'; 
    end if;

    -- 3. check if self-appraisals are submitted (one per goal)
    select count(sa.self_appraisal_id) 
    into v_appraisal_count 
    from `self_appraisals` sa
    join `goals` g on sa.goal_id = g.goal_id
    where g.employee_id = p_employee_id and g.cycle_id = p_cycle_id;
    
    if v_appraisal_count < v_goal_count then 
        return '3. awaiting self-appraisal'; 
    end if;

    -- 4. check if manager reviews are submitted (one per goal)
    select count(mr.review_id) 
    into v_review_count 
    from `manager_reviews` mr
    join `goals` g on mr.goal_id = g.goal_id
    where g.employee_id = p_employee_id and g.cycle_id = p_cycle_id;
    
    if v_review_count < v_goal_count then 
        return '4. awaiting manager review'; 
    end if;

    -- 5. check if final rating is published
    select count(*) 
    into v_final_rating 
    from `final_ratings` 
    where `employee_id` = p_employee_id and `cycle_id` = p_cycle_id;
    
    if v_final_rating = 0 then 
        return '5. awaiting final rating'; 
    end if;

    -- 6. all steps are done
    return '6. completed';
end//

delimiter ;

