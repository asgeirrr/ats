#! /usr/bin/env lua

-- This program sets pwm of Active thermal Solution for RockPro64
--
-- Nota :
-- Temperature can be more than real because of self heating
----------------------------------------------------------------------
-- Copyright (c) 2018 Carlos Domingues, aka tuxd3v <tuxd3v@sapo.pt>
-- 

---- Tests Done
--
-- This tool was tested 24x7, for more than a month, under Full Load, with:
-- < Minimal Debian Strech release > by ayufan

---- Require Sleep Functions to dynamic link against
--
require("sleep");

----
---- Thermal Global Variables
---

---   Path locations for control..
--

	-- CPU Thermal Zone[ String ]
	THERMAL0_CTL = "N/A";
	-- GPU Thermal Zone[ String ]
	THERMAL1_CTL = "N/A";
	-- FAN Control[ String ]
	FAN_CTL      = "N/A";

---   Update thermal,pwm values..
--

	-- Fan Pwm Value[ Integer ]
	FAN_PWM   = 0
	-- CPU  Thermal Zone[ Integer ]
	THERMAL_0 = 65
	-- GPU Thermal Zone [ Integer ]
	THERMAL_1 = 64

--- Active Solution, 2 profiles[ smallerfan,tallerfan ]
--

--- Chose Fan profile,
--  1 - smaller fan( ~10 mm taller )
--  2 - talller fan( ~20 mm taller )
	FANSPEC = 1

--- Entire Range of values, calculated on aplication startup, that will be used at runtime.
--

	-- PWM ratio, calculated based on interpolated values inside normal envelope, and some other values outside[ Global table of integer types ]
	PWM_RATIO={}
	-- Sleep timer( in seconds ), used for sleeping with Fan Stoped[ Global table of integer types ]
	QUIET={}
	-- Sleep timer( in seconds ), used for sleeping with Fan Running[ Global table of integer types ]
	RUN={}

----
---- Core Functions
---

--- Find Device sysfs location
--
function getConditions(  therm0_ctl, therm1_ctl, fan_ctl )
 	local handle = io.open( therm0_ctl , "r")
	if ( handle ~= nil )
	then
		THERMAL0_CTL = therm0_ctl
		handle:close()
	else
		THERMAL0_CTL = "ERROR"
		return 1
	end
 	handle = io.open( therm1_ctl , "r")
	if ( handle ~= nil )
	then
		THERMAL1_CTL = therm1_ctl
		handle:close()
	else
		THERMAL1_CTL = "ERROR"
		return 1
	end
 	handle = io.open( fan_ctl , "r")
	if ( handle ~= nil )
	then
		FAN_CTL = fan_ctl
		handle:close()
	else
		FAN_CTL = "ERROR"
		return 1
	end
	return 0
end

-- Set Fan PWM value[ integer ]
-- 
function setFanpwm( value )
    local RETURN = "N/A";
	local handle = io.open( FAN_CTL , "w")
	if ( handle ~= nil )
	then
		RETURN = handle:write( value .. "" )
		handle:close()
		if( RETURN ~= nil or RETURN ~= "N/A" )
		then
			getFanpwm()
			if( tonumber( FAN_PWM ) == value )
			then
				FAN_PWM = value
				return 0
			end
	end
    end
    FAN_PWM = 0
    return 1
end

-- Get Fan PWM value[ integer ]
-- 
function getFanpwm()
	local RETURN = "N/A";
	local handle = io.open( FAN_CTL , "r")
	if ( handle ~= nil )
	then
		RETURN = handle:read("*a")
		handle:close()
		if( RETURN ~= nil and RETURN ~= "N/A" )
		then
			FAN_PWM = tonumber( RETURN )
			return 0
		end
	end
	FAN_PWM = 0
	return 1
end

-- Get Thernal Values[ integer ]
-- 
function getThermal()
	local RETURN = "N/A";
	local handle = io.open( THERMAL0_CTL , "r" )
	if ( handle ~= nil )
	then
		RETURN = handle:read( "*a" )
		handle:close()
		if( RETURN ~= nil and RETURN ~= "N/A" )
		then
			THERMAL_0 = tonumber( RETURN  // 1000 )
		else
			THERMAL_0 = 65
		end
	else
			THERMAL_0 = 65
	end
	RETURN = "N/A";
	handle = io.open( THERMAL1_CTL .. "", "r" )
	if ( handle ~= nil )
	then
		RETURN = handle:read( "*a" )
		handle:close()
		if( RETURN ~= nil and RETURN ~= "N/A" )
		then
			THERMAL_1 = tonumber( RETURN  // 1000 )
			return 0
		else
			THERMAL_1 = 65
		end
	else
		THERMAL_1 = 65
	end
	return 1
end

---- Feature Functions
---

--- Function using Linear Interpolated Method
--

-- Predefind Triggers Range, were Active thermal Service stops/start Fan - QUIET,RUN
function buildTriggers()
	-- Local table, with 2 diferent pwm 'Response Curves' functions
	local fanSpec = {
		smallerFan	= function( temp ) return math.ceil( 40 + ( 215 / 21 ) * ( temp - 39 ) ) end,
		tallerFan	= function( temp ) return math.ceil( 40 + ( 215 / 31 ) * ( temp - 39 ) ) end
	}
	for i = 0,( ABSOLUTE_MAX_THERMAL_TEMP + 10 ),1
	do
		if( i >= 0 and i < MIN_THERMAL_TEMP )
		then
			PWM_RATIO[ i ]	= 0
			QUIET[ i ]		= 120
			RUN[ i ]		= 6
		elseif( i >= MIN_THERMAL_TEMP and i <= MAX_CONTINUOUS_THERMAL_TEMP )
		then
			-- Calculate PWM values based on 2 functions with diferent pwm 'Response Curves'
	  		PWM_RATIO[ i ]	= fanSpec[ FANSPEC ]( i )
	  		if ( i <= 45 )
	  		then
	  			QUIET[ i ]	= 90
	  			RUN[ i ]	= 10
	  		elseif( i <= 50 )
	  		then
	  			QUIET[ i ]	= 45
	  			RUN[ i ]	= 20
	  		elseif( i <= 55 )
	  		then
				QUIET[ i ]	= 40
	  			RUN[ i ]	= 30
	  		elseif( i <= 60 )
	  		then
				QUIET[ i ]	= 10
	  			RUN[ i ]	= 60
	  		end	
	  	elseif ( i > MAX_CONTINUOUS_THERMAL_TEMP )
	  	then
	  		PWM_RATIO[ i ]	= 255
	  		QUIET[ i ]		= 6
	  		RUN[ i ]		= 120
	  	end
	end
end
----------------------------
---- Variables and Functions to Deamonize.
--
--

function createLock()
	local RETURN = "N/A"
	local handle = io.open( "/var/lock/fanctl.lock" , "r")
	if ( handle == nil )
	then
		handle:close()
		RETURN = os.execute("echo $BASHPID;")
		ppid   = tonumber( RETURN )
		handle = io.open( "/var/lock/fanctl.lock" , "w")
		handle:write( RETURN .. "" )
		handle:close()
		return 0
	end
	handle:close()
	return 1
end

---- MAIN ----
----
--

---- Check Configurations
--
-- if( createLock() == 1 ){
--	print( "fanctl is already running.." )
--	print( "exit 1" )
--	os.exit(1);
--}

therm0_ctl = "/sys/class/thermal/thermal_zone0/temp"
therm1_ctl = "/sys/class/thermal/thermal_zone1/temp"
fan_ctl    = "/sys/class/hwmon/hwmon0/pwm1"
if( getConditions( therm0_ctl, therm1_ctl, fan_ctl ) == 1 )
then
	io.write( string.format("getConditions: Warning, Couldnt get sysfs Locations:\n%s\n%s\n%s\n\n", therm0_ctl, therm1_ctl, fan_ctl ))
	io.write( string.format("getConditions: Warning, Values { THERMAL0_CTL, THERMAL1_CTL, FAN_CTL }: %s, %s, %s\n", THERMAL0_CTL, THERMAL1_CTL, FAN_CTL ))
	io.write( string.format("exit 1\n"))
	os.exit(1)
end

---- Temperature Parameters
--
-- By Experience, without Underclock, with cpufreq Scalling 'Ondemand',
-- And with all CPUs at 100%, the temperature should not grow more than ~57/58C,
-- But it depends of the HeatSink used and also the Fan characteristics..and the environment around..

-- Max Temperatue Allowed on CPU, Above this Threshold, machine will shutdown
ABSOLUTE_MAX_THERMAL_TEMP	= 70

-- Max Temperature Allowed for adjusting fan pwm( On this threshold, and above, fan is always on MaxValue )
MAX_CONTINUOUS_THERMAL_TEMP	= 60
-- Min Temperature  threshold to activate Fan
MIN_THERMAL_TEMP			= 39

---- PWM Parameters
--
-- Min PWM alue, to Stop Fan.
STOP_FAN_PWM	= 0
-- Max PWM value possible
MAX_FAN_PWM		= 255
-- Adjust conform your Fan specs, some neds greater values, others work with less current
MIN_FAN_PWM		= 30

---- Initial Temperature
-- For Safety Reasons,
-- It Starts with 'MAX_CONTINUOUS_THERMAL_TEMP' limit, because we could not be able to read correctly the temps...
-- 
TEMP			= MAX_CONTINUOUS_THERMAL_TEMP

-- In the absence of proper Active Thermal Solution, to cool down( weak or dead fan? ),
-- It will adjust temps only until 'ABSOLUTE_MAX_THERMAL_TEMP' were reached, then were it Shutdown in 10s( for safety reasons.. )


-- Don't Start Fan with Big initial jump.. 
setFanpwm( 130 )
msleep( 200 )
setFanpwm( 190 )

-- Build triggers to use
buildTriggers()

-- Loop to Active Control Temps..
--
while true
do
	-- Sleeping with Fan OFF, until next cicle
	sleep( QUIET[ TEMP ] )
	
	-- Aquire  { CPU, GPU } -> THERMAL_{ 0, 1 } values
	getThermal()
	-- Use  Biggest Thermal Value from THERMAL_{0,1}
	if( THERMAL_0 > THERMAL_1 ) then TEMP = THERMAL_0 else TEMP = THERMAL_1 end
	
	-- Get PWM_RATIO from Table
	INSTANT_RATIO = PWM_RATIO[ TEMP ]
	
	-- If temp doesnt change...don't update it..
	if( INSTANT_RATIO ~= FAN_PWM )
	then
		if( FAN_PWM < 1 )
		then
			-- When stopped, it needs more power to start...
			setFanpwm( 130 )
			msleep( 200 )
			setFanpwm( 190 )
			sleep( 1 )
		end
		setFanpwm( INSTANT_RATIO )
	end
	
	-- Temp Above threshold to Underclock Frequencies
	if( TEMP >= ABSOLUTE_MAX_THERMAL_TEMP )
	then
		-- Temp is Critically Above 'ABSOLUTE_MAX_THERMAL_TEMP'
		os.execute( "sleep 10 && shutdown -h +0 \"Warning: Temperature **ABOVE** 'ABSOLUTE MAX THERMAL TEMP' ( " .. ABSOLUTE_MAX_THERMAL_TEMP .. "°C )\" &")
		io.write( string.format( "Warning: SHUTTING DOWN in 10s\n" ) )
		io.write( string.format( "Warning: Temperature **ABOVE** 'ABSOLUTE MAX THERMAL TEMP' (" .. ABSOLUTE_MAX_THERMAL_TEMP .. "°C )\n" ) )
		io.write( string.format( "Warning: Temperature **ABOVE** 'ABSOLUTE MAX THERMAL TEMP' (" .. ABSOLUTE_MAX_THERMAL_TEMP .. "°C )\n" ) )
		io.write( string.format( "Warning: Temperature **ABOVE** 'ABSOLUTE MAX THERMAL TEMP' (" .. ABSOLUTE_MAX_THERMAL_TEMP .. "°C )\n" ) )
		io.write( string.format( "Warning: Temperature **ABOVE** 'ABSOLUTE MAX THERMAL TEMP' (" .. ABSOLUTE_MAX_THERMAL_TEMP .. "°C )\n" ) )
		io.write( string.format( "Warning: Temperature **ABOVE** 'ABSOLUTE MAX THERMAL TEMP' (" .. ABSOLUTE_MAX_THERMAL_TEMP .. "°C )\n" ) )
		io.write( string.format( "Warning: Temperature **ABOVE** 'ABSOLUTE MAX THERMAL TEMP' (" .. ABSOLUTE_MAX_THERMAL_TEMP .. "°C )\n" ) )
		io.write( string.format( "Warning: Temperature **ABOVE** 'ABSOLUTE MAX THERMAL TEMP' (" .. ABSOLUTE_MAX_THERMAL_TEMP .. "°C )\n" ) )
		io.write( string.format( "Warning: Temperature **ABOVE** 'ABSOLUTE MAX THERMAL TEMP' (" .. ABSOLUTE_MAX_THERMAL_TEMP .. "°C )\n" ) )
		io.write( string.format( "exit 1\n" ) )
	end
	
	-- sleeping with Fan ON until next cycle
	sleep( RUN[ TEMP ] )
	-- Stop Fan
	setFanpwm( 0 )
end

os.exit( 1 );