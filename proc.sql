use `apas_db`;

delimiter //

-- =================================================================
-- procedure 1: sp_approvegoal (security & business logic)
-- securely approves a goal, checking if the caller is the correct manager.
-- =================================================================
create procedure `sp_approvegoal`(
    in p_manager_id int,  -- the id of the manager *performing* the action
    in p_goal_id int,      -- the id of the goal being approved
    in p_feedback text     -- the manager's approval comments
)
modifies sql data begin
    declare v_employee_id int;
    declare v_is_authorized boolean;

    -- set the app_user_id for the audit trigger
    -- the manager *is* the user in this context.
    set @app_user_id = p_manager_id;

    -- find out which employee this goal belongs to
    select `employee_id` into v_employee_id 
    from `goals` 
    where `goal_id` = p_goal_id;

    -- use our function to check if this manager (p_manager_id)
    -- is the actual manager of the employee (v_employee_id)
    set v_is_authorized = fn_ismanagerof(p_manager_id, v_employee_id);

    -- only perform the update if they are authorized
    if v_is_authorized = true then
        update `goals`
        set 
            `goal_status` = 'approved',
            `manager_feedback` = p_feedback
        where 
            `goal_id` = p_goal_id;
    else
        -- if not authorized, raise an error
        signal sqlstate '45000' 
        set message_text = 'unauthorized: you are not the manager for this employee.';
    end if;
end//

-- =================================================================
-- procedure 2: sp_calculatefinalratings (batch job)
-- loops through all employees in a cycle and calculates their final score
-- using our fn_getemployeeweightedscore function.
-- =================================================================
create procedure `sp_calculatefinalratings`(
    in p_cycle_id int, -- the cycle to finalize
    in p_admin_id int  -- the hr admin *running* this batch job (for auditing)
)
modifies sql data begin
    -- variables for the loop
    declare v_done int default false;
    declare v_employee_id int;
    declare v_final_score decimal(5,2);

    -- cursor to iterate over all employees (except the 'system' user)
    declare cur_employees cursor for 
        select `employee_id` 
        from `employees` 
        where `role_id` != 1; -- 1 = 'system' role

    -- handler to exit the loop when the cursor is empty
    declare continue handler for not found set v_done = true;

    -- set the app_user_id for all audit triggers that fire
    set @app_user_id = p_admin_id;

    open cur_employees;

    read_loop: loop
        fetch cur_employees into v_employee_id;
        
        if v_done then
            leave read_loop;
        end if;

        -- 1. call the function to get the calculated score
        set v_final_score = fn_getemployeeweightedscore(v_employee_id, p_cycle_id);

        -- 2. insert the score. if it already exists, update it.
        -- this makes the procedure safe to re-run.
        insert into `final_ratings` 
            (`employee_id`, `cycle_id`, `weighted_score`)
        values 
            (v_employee_id, p_cycle_id, v_final_score)
        on duplicate key update 
            `weighted_score` = v_final_score;

    end loop;

    close cur_employees;
end//

-- =================================================================
-- procedure 3: sp_getemployeeperformancereport (data aggregation)
-- gathers all data for a single employee's report in one call.
-- this procedure will return four separate result sets.
-- =================================================================
create procedure `sp_getemployeeperformancereport`(
    in p_employee_id int, -- the employee *being viewed*
    in p_cycle_id int,
    in p_accessor_id int  -- the person *viewing* the report (for auditing)
)
modifies sql data begin
    -- set the user for the audit log
    set @app_user_id = p_accessor_id;

    -- log the fact that this sensitive report was viewed.
    -- we do this *inside* the procedure because there is no 'select' trigger.
    insert into `audit_logs` (`user_id`, `action`, `details`)
    values (
        @app_user_id,
        'report_viewed',
        concat('viewed performance report for employee: ', p_employee_id, ' in cycle: ', p_cycle_id)
    );

    -- 1. final summary (score & rank)
    select * from `final_ratings` 
    where `employee_id` = p_employee_id and `cycle_id` = p_cycle_id;

    -- 2. goals & manager reviews
    select 
        g.goal_title, 
        g.goal_description, 
        g.goal_weightage, 
        mr.rating, 
        mr.feedback
    from `goals` g
    left join `manager_reviews` mr on g.goal_id = mr.goal_id
    where 
        g.employee_id = p_employee_id 
        and g.cycle_id = p_cycle_id
        and g.goal_status != 'pending_approval';

    -- 3. self-appraisal comments
    select 
        g.goal_title, 
        sa.comments, 
        sa.document_link
    from `self_appraisals` sa
    join `goals` g on sa.goal_id = g.goal_id
    where 
        g.employee_id = p_employee_id 
        and g.cycle_id = p_cycle_id;

    -- 4. 360-degree feedback (if any)
    select 
        e.employee_name as reviewer_name, 
        f.rating, 
        f.comments
    from `feedback_360` f
    join `employees` e on f.reviewer_id = e.employee_id
    where 
        f.employee_id = p_employee_id 
        and f.cycle_id = p_cycle_id;
end//

-- =================================================================
-- PROCEDURE 4: sp_GetDepartmentPerformanceReport
-- Returns a summary of all departments for a given cycle.
-- =================================================================
CREATE PROCEDURE `sp_GetDepartmentPerformanceReport`(
    IN p_cycle_id INT
)
READS SQL DATA
BEGIN
    SELECT
        d.department_name,
        COUNT(report.employee_id) AS 'employees_rated',
        AVG(report.weighted_score) AS 'average_score',
        MAX(report.weighted_score) AS 'highest_score'
    FROM
        `departments` d
    LEFT JOIN
        (
            -- This is your nested query from before
            SELECT
                e.employee_id,
                e.department_id,
                fr.weighted_score
            FROM
                `final_ratings` fr
            JOIN
                `employees` e ON fr.employee_id = e.employee_id
            WHERE
                fr.cycle_id = p_cycle_id -- Use the parameter
        ) AS report ON d.department_id = report.department_id
    GROUP BY
        d.department_name
    ORDER BY
        average_score DESC;
END//

delimiter ;

