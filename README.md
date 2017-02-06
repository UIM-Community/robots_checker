# robots_checker
CA UIM Robots_checker (check probes, and do callback on it). This probe has been created to do self monitoring of CA UIM Hubs and robots.

> Warning this probe only work on hub, the probe do local checkup with nimRequest only (dont use to do remote checkup). 

# Features 

- Test Callback on each probe of each robots.

> Feel free to PR new monitoring 

# Installation and configuration guide 

> First of all, dont use nim_login and nim_password if you package the probe. Use these fields when you run the script manually on the system. 

Dont forget you need perluim R4.0 framework for this probe. Find the framework [HERE](https://github.com/fraxken/perluim)

### Setup section 

| Section | Key | Values | Description |
| --- | --- | --- | --- |
| setup | domain | string | CA UIM Domain |
| setup | audit | 1 - 0 |When audit is set to 1, the probe does not generate new alarms (cool to test in production the first time). |
| setup | callback_retry_count | number | Number of retries of primary callbacks (getrobots and probeslist). |
| setup | output_directory | string | the name of output directory. | 
| setup | output_cache_time | number | the cache time in second for output directory. |

### Sample configuration 

```xml
<setup>
    domain = DOMAIN
    audit = 0
    callback_retry_count = 3
    nim_login = login
    nim_password = password
    output_directory = output
    output_cache_time = 432000
</setup>
<monitoring>
    alarms_probes_down = yes
    alarm_severity = 2
    alarm_subsys = 1.1.20
</monitoring>
<probes_list>
    <cdm>
        callback = _status
    </cdm>
    <ntevl>
        callback = _status
    </ntevl>
    <dirscan>
        callback = _status
    </dirscan>
    <logmon>
        callback = _status
    </logmon>
    <spooler>
        callback = _status 
    </spooler>
    <hdb>
        callback = _status 
    </hdb> 
    <ntservices>
        callback = _status 
    </ntservices> 
    <processes>
        callback = _status 
    </processes>
</probes_list>
```
