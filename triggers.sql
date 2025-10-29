delimiter //

-- I. triggers for `goals`
-- 1. trigger to log the creation of a new goal
create trigger `trg_goals_after_insert`
after insert on `goals`
for each row begin
    insert into `audit_logs` (`user_id`, `action`, `details`)
    values (
        coalesce(@app_user_id, 1),
        'goal_created',
        concat('new goal created with id: ', new.goal_id, ' for employee: ', new.employee_id)
    );
end//

-- 2. trigger to log updates to a goal (e.g., status change, feedback added)
create trigger `trg_goals_after_update`
after update on `goals`
for each row begin
    declare changes text;
    set changes = concat('updated goal id: ', new.goal_id, '. ');

    -- check if the status was changed, which is a key event
    if old.goal_status <> new.goal_status then
        set changes = concat(changes, 'status changed from ''', old.goal_status, ''' to ''', new.goal_status, '''. ');
    end if;
    
    -- check if manager feedback was added or changed
    if old.manager_feedback is null and new.manager_feedback is not null then
        set changes = concat(changes, 'manager feedback was added.');
    elseif old.manager_feedback <> new.manager_feedback then
        set changes = concat(changes, 'manager feedback was updated.');
    end if;

    -- only insert into audit log if there was a meaningful change
    if old.goal_status <> new.goal_status or old.manager_feedback <> new.manager_feedback then
        insert into `audit_logs` (`user_id`, `action`, `details`)
        values (
            coalesce(@app_user_id, 1),
            'goal_updated',
            changes
        );
    end if;
end//

-- 3. trigger to log the deletion of a goal
create trigger `trg_goals_after_delete`
after delete on `goals`
for each row
begin
    insert into `audit_logs` (`user_id`, `action`, `details`)
    values (
        coalesce(@app_user_id, 1),
        'goal_deleted',
        concat('goal deleted with id: ', old.goal_id, ', title: ''', old.goal_title, '''. was for employee: ', old.employee_id)
    );
end//


-- II. triggers for the `final_ratings` table
-- 1.  trigger to log the creation of a final rating
create trigger `trg_final_ratings_after_insert`
after insert on `final_ratings`
for each row
begin
    insert into `audit_logs` (`user_id`, `action`, `details`)
    values (
        coalesce(@app_user_id, 1), -- default to user 1 ('system_audit') if not set
        'final_rating_created',
        concat('final rating created for employee id: ', new.employee_id, ' in cycle: ', new.cycle_id, '. score: ', new.weighted_score)
    );
end//

-- 2.  trigger to log updates to a final rating (a very sensitive action)
create trigger `trg_final_ratings_after_update`
after update on `final_ratings`
for each row begin
    -- we should log any update to this table, even if values are the same
    insert into `audit_logs` (`user_id`, `action`, `details`)
    values (
        coalesce(@app_user_id, 1),
        'final_rating_updated',
        concat('final rating updated for employee id: ', new.employee_id, '. old score: ', old.weighted_score, ', new score: ', new.weighted_score, '. old rank: ''', old.final_rank, ''', new rank: ''', new.final_rank, '''.')
    );
end//

-- 3.  trigger to log the deletion of a final rating (a very sensitive action)
create trigger `trg_final_ratings_after_delete`
after delete on `final_ratings`
for each row begin
    insert into `audit_logs` (`user_id`, `action`, `details`)
    values (
        coalesce(@app_user_id, 1), -- default to user 1 ('system_audit') if not set
        'final_rating_deleted',
        concat('final rating deleted for employee id: ', old.employee_id, ' in cycle: ', old.cycle_id, '. score was: ', old.weighted_score, ', rank was: ''', old.final_rank, '''.')
    );
end//

delimiter ;