# @summary This manifest sets up a script and cron job to populate
#   the `os_patching` fact.
#
# @param patch_data_owner [String]
#   User name for the owner of the patch data
#
# @param patch_data_group [String] 
#   Group name for the owner of the patch data
#
# @param patch_cron_user [String]
#   User who runs the cron job
#
# @param manage_delta_rpm [Boolean]
#   Should the deltarpm package be managed by this module on RedHat family nodes?
#   If `true`, use the parameter `delta_rpm` to determine how it should be manged
#
# @param delta_rpm [Enum]
#   If managed, what should the delta_rpm package set to?
#
# @parammanage_yum_plugin_security [Boolean]
#   Should the yum_plugin_security package be managed by this module on RedHat family nodes?
#   If `true`, use the parameter `yum_plugin_security` to determine how it should be manged
#
# @param yum_plugin_security [Enum]
#   If managed, what should the yum_plugin_security package set to?
#
# @param reboot_override [Variant]
#   Controls on a node level if a reboot should/should not be done after patching.
#   This overrides the setting in the task
#
# @param blackout_windows [Hash]
#   A hash containing the patch blackout windows, which prevent patching.
#   The dates are in full ISO8601 format.
#
# @option blackout_windows [String] :title
#   Name of the blackout window
#
# @option blackout_windows [String] :start
#   Start of the blackout window (ISO8601 format)
#
# @option blackout_windows [String] :end
#   End of the blackout window (ISO8601 format)
#
# @param patch_window [String]
#   A freeform text entry used to allocate a node to a specific patch window (Optional)
#
# @param patch_cron_hour
#   The hour(s) for the cron job to run (defaults to absent, which means '*' in cron)
#
# @param patch_cron_month
#   The month(s) for the cron job to run (defaults to absent, which means '*' in cron)
#
# @param patch_cron_monthday
#   The monthday(s) for the cron job to run (defaults to absent, which means '*' in cron)
#
# @param patch_cron_weekday
#   The weekday(s) for the cron job to run (defaults to absent, which means '*' in cron)
#
# @param patch_cron_min
#   The min(s) for the cron job to run (defaults to a random number between 0 and 59)
#
# @example assign node to 'Week3' patching window, force a reboot and create a blackout window for the end of the year
#   class { 'os_patching':
#     patch_window     => 'Week3',
#     reboot_override  => 'always',
#     blackout_windows => { 'End of year change freeze':
#       {
#         'start': '2018-12-15T00:00:00+1000',
#         'end': '2019-01-15T23:59:59+1000',
#       }
#     },
#   }
#
# @example An example profile to setup patching, sourcing blackout windows from hiera
#   class profiles::soe::patching (
#     $patch_window     = undef,
#     $blackout_windows = undef,
#     $reboot_override  = undef,
#   ){
#     # Pull any blackout windows out of hiera
#     $hiera_blackout_windows = lookup('profiles::soe::patching::blackout_windows',Hash,hash,{})
#
#     # Merge the blackout windows from the parameter and hiera
#     $full_blackout_windows = $hiera_blackout_windows + $blackout_windows
#
#     # Call the os_patching class to set everything up
#     class { 'os_patching':
#       patch_window     => $patch_window,
#       reboot_override  => $reboot_override,
#       blackout_windows => $full_blackout_windows,
#     }
#   }
#
# @example JSON hash to specify a change freeze from 2018-12-15 to 2019-01-15
#   {"End of year change freeze": {"start": "2018-12-15T00:00:00+1000", "end": "2019-01-15T23:59:59+1000"}}
#
# @example Run patching on the node `centos.example.com` using the smart reboot option
#   puppet task run os_patching::patch_server --params '{"reboot": "smart"}' --nodes centos.example.com
#
class os_patching (
  String $patch_data_owner            = 'root',
  String $patch_data_group            = 'root',
  String $patch_cron_user             = $patch_data_owner,
  Boolean $manage_delta_rpm           = false,
  Boolean $manage_yum_plugin_security = false,
  Enum['installed', 'absent', 'purged', 'held', 'latest'] $delta_rpm = 'installed',
  Enum['installed', 'absent', 'purged', 'held', 'latest'] $yum_plugin_security = 'installed',
  Optional[Variant[Boolean, Enum['always', 'never', 'patched', 'smart', 'default']]] $reboot_override = 'default',
  Optional[Hash] $blackout_windows = undef,
  $patch_window                    = undef,
  $patch_cron_hour                 = absent,
  $patch_cron_month                = absent,
  $patch_cron_monthday             = absent,
  $patch_cron_weekday              = absent,
  $patch_cron_min                  = fqdn_rand(59),
){
  $fact_cmd = '/usr/local/bin/os_patching_fact_generation.sh'
  $fact_upload ='/opt/puppetlabs/bin/puppet facts upload'

  if ( $::kernel != 'Linux' ) { fail('Unsupported OS') }

  if ( $::osfamily == 'RedHat' and $manage_delta_rpm) {
    package { 'deltarpm':
      ensure => $delta_rpm,
    }
  }

  if ( $::osfamily == 'RedHat' and $manage_yum_plugin_security) {
    package { 'yum-plugin-security':
      ensure => $yum_plugin_security,
    }
  }

  file { '/opt/puppetlabs/facter/facts.d/os_patching.yaml':
    ensure => absent,
  }

  file { '/etc/os_patching':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    notify => Exec[$fact_cmd],
  }

  unless defined(Class['os_patching::block']) {
    file { '/etc/os_patching/block.conf':
      ensure => absent,
    }
  }

  file { $fact_cmd:
    ensure => present,
    owner  => $patch_data_owner,
    group  => $patch_data_group,
    mode   => '0700',
    source => "puppet:///modules/${module_name}/os_patching_fact_generation.sh",
    notify => Exec[$fact_cmd],
  }

  exec { $fact_cmd:
    user        => $patch_data_owner,
    group       => $patch_data_group,
    refreshonly => true,
    require     => File[$fact_cmd],
  }

  cron { 'Cache patching data':
    ensure   => present,
    command  => $fact_cmd,
    user     => $patch_cron_user,
    hour     => $patch_cron_hour,
    minute   => $patch_cron_min,
    month    => $patch_cron_month,
    monthday => $patch_cron_monthday,
    weekday  => $patch_cron_weekday,
    require  => File[$fact_cmd],
  }

  cron { 'Cache patching data at reboot':
    ensure  => present,
    command => $fact_cmd,
    user    => $patch_cron_user,
    special => 'reboot',
    require => File[$fact_cmd],
  }

  $patch_window_file = '/etc/os_patching/patch_window'
  if ( $patch_window ) {
    if ($patch_window !~ /[A-Za-z0-9\-_ ]+/ ){
      fail ('The patch window can only contain alphanumerics, space, underscore and dash')
    }

    file { $patch_window_file:
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => $patch_window,
      require => File['/etc/os_patching'],
      notify  => Exec[$fact_upload],
    }
  } else {
    file { $patch_window_file:
      ensure => absent,
      notify => Exec[$fact_upload],
    }
  }

  $reboot_override_file = '/etc/os_patching/reboot_override'
  if ( $reboot_override != undef ) {
    case $reboot_override {
      true:     { $reboot_override_value = 'always' }
      false:    { $reboot_override_value = 'never' }
      default:  { $reboot_override_value = $reboot_override }
    }

    file { $reboot_override_file:
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => $reboot_override_value,
      require => File['/etc/os_patching'],
      notify  => Exec[$fact_upload],
    }
  } else {
    file { $reboot_override_file:
      ensure => absent,
      notify => Exec[$fact_upload],
    }
  }

  $blackout_window_file = '/etc/os_patching/blackout_windows'
  if ( $blackout_windows ) {
    # Validate the information in the blackout_windows hash
    $blackout_windows.each | String $key, Hash $value | {
      if ( $key !~ /^[A-Za-z0-9\-_ ]+$/ ){
        fail ('Blackout description can only contain alphanumerics, space, dash and underscore')
      }
      if ( $value['start'] !~ /^[\d:T\-\\+]*$/ ){
        fail ('Blackout start time must be in ISO 8601 format')
      }
      if ( $value['end'] !~ /^[\d:T\-\\+]*$/ ){
        fail ('Blackout end time must be in ISO 8601 format')
      }
      if ( $value['start'] > $value['end'] ){
        fail ('Blackout end time must after the start time')
      }
    }
    file { $blackout_window_file:
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template("${module_name}/blackout_windows.erb"),
      require => File['/etc/os_patching'],
      notify  => Exec[$fact_upload],
    }
  } else {
    file { $blackout_window_file:
      ensure => absent,
      notify => Exec[$fact_upload],
    }
  }

  exec { $fact_upload:
    refreshonly => true,
  }
}
