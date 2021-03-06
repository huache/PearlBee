=head

Author: Andrei Cacio
Email: andrei.cacio@evozon.com

=cut

package PearlBee::Admin::User;

use Dancer2;
use Dancer2::Plugin::DBIC;

use PearlBee::Helpers::Pagination qw(get_total_pages get_previous_next_link generate_pagination_numbering);
use PearlBee::Helpers::Util qw(create_password);

use Email::Template;
use DateTime;

get '/admin/users' => sub { redirect session('app_url') . '/admin/users/page/1'; };

=head

List all users

=cut

get '/admin/users/page/:page' => sub {

  my $nr_of_rows  = 5; # Number of posts per page
  my $page        = params->{page} || 1;
  my @users;
  if (session('multiuser')) {
    @users = resultset('User')->search({}, { order_by => { -desc => "register_date" }, rows => $nr_of_rows, page => $page });
  } else {
    @users = resultset('User')->search({ status => { '!=' => 'pending' } }, { order_by => { -desc => "register_date" }, rows => $nr_of_rows, page => $page });
  }
  
  
  my $count       = resultset('View::Count::StatusUser')->first;
  
  my ($all, $activated, $deactivated, $suspended, $pending) = $count->get_all_status_counts;
  
  if (! session('multiuser')) {
    # do not count 'pending' users
    my $count_pending = resultset('User')->search({ status => 'pending' })->count;
    $all -= $count_pending;
  }
  

  # Calculate the next and previous page link
  my $total_pages                 = get_total_pages($all, $nr_of_rows);
  my ($previous_link, $next_link) = get_previous_next_link($page, $total_pages, '/admin/users');

  # Generating the pagination navigation
  my $total_users     = $all;
  my $posts_per_page  = $nr_of_rows;
  my $current_page    = $page;
  my $pages_per_set   = 7;
  my $pagination      = generate_pagination_numbering($total_users, $posts_per_page, $current_page, $pages_per_set);

  template '/admin/users/list',
    {
      users         => \@users,
      all           => $all, 
      activated     => $activated,
      deactivated   => $deactivated,
      suspended     => $suspended,
      pending       => $pending,
      page          => $page,
      next_link     => $next_link,
      previous_link => $previous_link,
      action_url    => 'admin/users/page',
      pages         => $pagination->pages_in_set
    },
    { layout => 'admin' };

};

=head

List all users grouped by status

=cut

get '/admin/users/:status/page/:page' => sub {

  my $nr_of_rows  = 5; # Number of posts per page
  my $page        = params->{page} || 1;
  my $status      = params->{status};
  my @users       = resultset('User')->search({ status => $status }, { order_by => { -desc => "register_date" }, rows => $nr_of_rows, page => $page });
  my $count       = resultset('View::Count::StatusUser')->first;
  
  my ($all, $activated, $deactivated, $suspended, $pending) = $count->get_all_status_counts;
  my $status_count                                = $count->get_status_count($status);
  
  if (! session('multiuser')) {
    # do not count 'pending' users
    my $count_pending = resultset('User')->search({ status => 'pending' })->count;
    $all -= $count_pending;
  }

  # Calculate the next and previous page link
  my $total_pages                 = get_total_pages($all, $nr_of_rows);
  my ($previous_link, $next_link) = get_previous_next_link($page, $total_pages, '/admin/users/' . $status);

  # Generating the pagination navigation
  my $total_users     = $status_count;
  my $posts_per_page  = $nr_of_rows;
  my $current_page    = $page;
  my $pages_per_set   = 7;
  my $pagination      = generate_pagination_numbering($total_users, $posts_per_page, $current_page, $pages_per_set);

  template '/admin/users/list',
    {
      users         => \@users,
      all           => $all, 
      activated     => $activated,
      deactivated   => $deactivated,
      suspended     => $suspended,
      pending       => $pending,
      page          => $page,
      next_link     => $next_link,
      previous_link => $previous_link,
      action_url    => 'admin/users/' . $status . '/page',
      pages         => $pagination->pages_in_set,
      status        => $status
    },
    { layout => 'admin' };

};

=head

Activate user

=cut

any '/admin/users/activate/:id' => sub {

  my $user_id = params->{id};
  my $user   = resultset('User')->find( $user_id );

  eval { $user->activate(); };

  redirect session('app_url') . '/admin/users';
};

=head

Deactivate user

=cut

any '/admin/users/deactivate/:id' => sub {

  my $user_id = params->{id};
  my $user   = resultset('User')->find( $user_id );

  eval { $user->deactivate(); };

  redirect session('app_url') . '/admin/users';
};

=head

Suspend user

=cut

any '/admin/users/suspend/:id' => sub {

  my $user_id = params->{id};
  my $user   = resultset('User')->find( $user_id );

  eval { $user->suspend(); };

  redirect session('app_url') . '/admin/users';
};

=head

Allow pending user

=cut

any '/admin/users/allow/:id' => sub {

  my $user_id = params->{id};
  my $user   = resultset('User')->find( $user_id );
  
  if ($user) {
    eval {
      my ($password, $pass_hash, $salt) = create_password();
      
      $user->update( {password => $pass_hash, salt => $salt} );
    
      $user->allow();
      
      Email::Template->send( config->{email_templates} . 'welcome.tt',
          {
              From    => config->{default_email_sender},
              To      => $user->email,
              Subject => config->{welcome_email_subject},
  
              tt_vars => {
                  role        => $user->role,
                  username    => $user->username,
                  password    => $password,
                  first_name  => $user->first_name,
                  app_url     => config->{app_url},
                  blog_name   => session('blog_name'),
                  signature   => config->{email_signature},
                  allowed     => 1,
              },
      }) or error "Could not send the email";
    };
  }

  redirect session('app_url') . '/admin/users';
};

=head

Add a new user

=cut

any '/admin/users/add' => sub {

  if ( params->{username} ) {

    eval {

      # Set the proper timezone
      my $dt       = DateTime->now;          
      my $settings = resultset('Setting')->first;
      $dt->set_time_zone( $settings->timezone );
      
      my ($password, $pass_hash, $salt) = create_password();
      my $username   = params->{username};
      my $email      = params->{email};
      my $first_name = params->{first_name};
      my $last_name  = params->{last_name};
      my $role       = params->{role};

      resultset('User')->create({
        username        => $username,
        password        => $pass_hash,
        salt            => $salt,        
        first_name      => $first_name,
        last_name       => $last_name,
        register_date   => join (' ', $dt->ymd, $dt->hms),
        role            => $role,
        email           => $email,
      });

      Email::Template->send( config->{email_templates} . 'welcome.tt',
        {
            From    => config->{default_email_sender},
            To      => $email,
            Subject => config->{welcome_email_subject},

            tt_vars => {
                role        => $role,
                username    => $username,
                password    => $password,
                first_name  => $first_name,
                app_url     => config->{app_url},
                blog_name   => session('blog_name'),
                signature   => config->{email_signature}
            },
        }) or error "Could not send the email";
    };

    error $@ if ( $@ );

    if ( $@ ) {
      template 'admin/users/add', 
        {
          warning => 'Something went wrong. Please contact the administrator.'
        }, 
        { layout => 'admin' };
    }
    else {
      template 'admin/users/add', 
        {
          success => 'The user was added succesfully and will be activated after he logs in.'
        }, 
        { layout => 'admin' };
    }
    
  }
  else {
    template 'admin/users/add', {},  { layout => 'admin' };
  }  
};

1;