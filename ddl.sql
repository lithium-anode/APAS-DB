create database if not exists `apas_db`;
use `apas_db`;

create table `departments` (
    `department_id` int unsigned auto_increment primary key,
    `department_name` varchar(255) not null unique,
    `created_at` timestamp default current_timestamp
);

-- store user roles (e.g., employee, manager, hr administrator)
create table `roles` (
    `role_id` int unsigned auto_increment primary key,
    `role_name` varchar(100) not null unique,
    `created_at` timestamp default current_timestamp
);

-- employee user accounts and profiles
create table `employees` (
    `employee_id` int unsigned auto_increment primary key,
    `employee_name` varchar(255) not null,
    `employee_email` varchar(255) not null unique,
    `password_hash` varchar(255) not null, -- storing hashed passwords as per security requirements
    `role_id` int unsigned not null,
    `department_id` int unsigned not null,
    `manager_id` int unsigned, -- self-referencing key for reporting line
    `created_at` timestamp default current_timestamp,
    `updated_at` timestamp default current_timestamp on update current_timestamp,
    foreign key (`role_id`) references `roles`(`role_id`) on delete restrict,
    foreign key (`department_id`) references `departments`(`department_id`) on delete restrict,
    foreign key (`manager_id`) references `employees`(`employee_id`) on delete set null
);

-- manage appraisal cycles (e.g., "annual review 2025")
create table `appraisal_cycles` (
    `cycle_id` int unsigned auto_increment primary key,
    `cycle_name` varchar(255) not null,
    `start_date` date not null,
    `end_date` date not null,
    `status` enum('inactive', 'active', 'closed') not null default 'inactive',
    `created_at` timestamp default current_timestamp
);

-- employee-set goals
create table `goals` (
    `goal_id` int unsigned auto_increment primary key,
    `employee_id` int unsigned not null,
    `cycle_id` int unsigned not null,
    `goal_title` varchar(255) not null,
    `goal_description` text,
    `goal_weightage` decimal(5,2) check (`goal_weightage` > 0 and `goal_weightage` <= 100),
    `goal_status` enum('pending_approval', 'approved', 'rejected', 'in_progress', 'completed') not null,
    `manager_feedback` text,
    `created_at` timestamp default current_timestamp,
    `updated_at` timestamp default current_timestamp on update current_timestamp,
    foreign key (`employee_id`) references `employees`(`employee_id`) on delete cascade,
    foreign key (`cycle_id`) references `appraisal_cycles`(`cycle_id`) on delete restrict
);

-- employee self-appraisals
create table `self_appraisals` (
    `self_appraisal_id` int unsigned auto_increment primary key,
    `goal_id` int unsigned not null,
    `employee_id` int unsigned not null,
    `comments` text,
    `document_link` varchar(2083), -- for supporting documents
    `submission_date` timestamp default current_timestamp,
    foreign key (`goal_id`) references `goals`(`goal_id`) on delete cascade,
    foreign key (`employee_id`) references `employees`(`employee_id`) on delete cascade
);

-- manager review of an employee's goal
create table `manager_reviews` (
    `review_id` int unsigned auto_increment primary key,
    `goal_id` int unsigned not null,
    `manager_id` int unsigned not null,
    `rating` tinyint unsigned check (`rating` >= 1 and `rating` <= 5),
    `feedback` text,
    `review_date` timestamp default current_timestamp,
    foreign key (`goal_id`) references `goals`(`goal_id`) on delete cascade,
    foreign key (`manager_id`) references `employees`(`employee_id`) on delete cascade
);

-- 360-degree feedback from peers
create table `feedback_360` (
    `feedback_id` int unsigned auto_increment primary key,
    `employee_id` int unsigned not null, -- the employee being reviewed
    `reviewer_id` int unsigned not null, -- the peer/colleague giving feedback
    `cycle_id` int unsigned not null,
    `rating` tinyint unsigned check (`rating` >= 1 and `rating` <= 5),
    `comments` text,
    `feedback_date` timestamp default current_timestamp,
    foreign key (`employee_id`) references `employees`(`employee_id`) on delete cascade,
    foreign key (`reviewer_id`) references `employees`(`employee_id`) on delete cascade,
    foreign key (`cycle_id`) references `appraisal_cycles`(`cycle_id`) on delete restrict,
    unique(`employee_id`, `reviewer_id`, `cycle_id`) -- ensures one reviewer gives only one 360-feedback per cycle
);

-- store final aggregated rating and rank
create table `final_ratings` (
    `rating_id` int unsigned auto_increment primary key,
    `employee_id` int unsigned not null,
    `cycle_id` int unsigned not null,
    `weighted_score` decimal(5,2) not null,
    `final_rank` varchar(50),
    `final_comments` text,
    `finalized_at` timestamp default current_timestamp,
    foreign key (`employee_id`) references `employees`(`employee_id`) on delete cascade,
    foreign key (`cycle_id`) references `appraisal_cycles`(`cycle_id`) on delete restrict,
    unique(`employee_id`, `cycle_id`) -- an employee can only have one final rating per cycle
);

-- auditing user actions as per security requirements
create table `audit_logs` (
    `log_id` bigint unsigned auto_increment primary key,
    `user_id` int unsigned not null,
    `action` varchar(255) not null, -- e.g., 'login', 'update_goal', 'submit_rating'
    `details` text, -- e.g., 'updated goal_id 123'
    `timestamp` timestamp default current_timestamp,
    foreign key (`user_id`) references `employees`(`employee_id`) on delete cascade
);
