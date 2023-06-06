#!/usr/bin/php
<?php

// load the parseDataFile
include_once('/usr/share/php/tbs/plugins/parse-data-file.php');

function usage()
{
	printf("usage: jmerge -c config -T var_template -D var_data -o output -t template -i datafile files [files]\n");
}

# command argument
$options = getopt('ho:t:i:c:T:D:');
#var_dump( $options );

# unset processed argv
$pruneargv = array();
foreach ($options as $option => $value) {
	foreach ($argv as $key => $chunk) {
		$regex = '/^'. (isset($option[1]) ? '--' : '-') . $option . '/';
		if ($chunk === $value && $argv[$key-1][0] === '-'
			|| preg_match($regex, $chunk)) {
			array_push($pruneargv, $key);
		}
	}
}
#var_dump( $pruneargv );
while ($key = array_pop($pruneargv))
	unset($argv[$key]);

#var_dump( $argv );

$argv = array_merge( $argv );
#var_dump( $argv );

# print arguments
#foreach ($argv as $key)
#{
#	printf("args: %s\n", $key);
#}

$config_file = "config.config";
$datafile = "php://stdin";
$template = 'runsheet.html';
$output   = '-';
$var_template = 'template';
$var_data = 'data';
if (isset($options['c']))
{
	$config_file = $options['c'];
}

if (isset($options['i']))
{
	$datafile = $options['i'];
}

if (isset($options['t']))
{
	$template = $options['t'];
}

if (isset($options['o']))
{
	$output = $options['o'];
}

if (isset($options['T']))
{
	$var_template = $options['T'];
}

if (isset($options['D']))
{
	$var_data = $options['D'];
}

# print arguments
#printf("datafile: %s\n", $datafile);
#printf("template: %s\n", $template);
$contents = file_get_contents($datafile);
#printf("contents: %s\n", $contents);
#for ($i = 1; $i < count($argv); $i++)
#{
#	#printf("args: %s\n", $key);
#	if (file_exists($argv[$i]))
#	{
#		$contents .= file_get_contents($argv[$i]);
#	}
#}

$Config = json_decode($contents, true);

$x = pathinfo($template);
// var_dump($x);
$template_filename = $x['filename'];
$template_ext = $x['extension'];

if (! ($datafile === "php://stdin") && !file_exists($datafile))
{
	usage();
	exit("Data file does not exist.\n");
	exit(0);
}

if (!file_exists($template))
{
	usage();
	printf("Template file [%s] does not exist.\n", $template);
	exit(0);
}

$global = array();
$sections = array();
$conf = array();

if (file_exists($config_file))
{
	$conf = parseDataFile($config_file);
	// Prepare some data for the global
	$global_data = $conf['global'];
	// print_r($global_data);
	$global[] = $global_data;
	//var_dump($global);

	$section_data = $conf['section'];
	// print_r($section_data);
	$sections[] = $section_data;
	//var_dump($sections);
	//var_dump($conf['section']);
	//foreach ($conf['section'] as &$section)
	//{
	//	printf("DBX,%s,%s,%s\n", $section{'sheet'},
	//		$section{'var_template'},
	//		$section{'var_data'});
	//}
}
else
{
	$conf['section'][0]['sheet'] = 'default';
	$conf['section'][0]['var_data'] = $var_data;
	$conf['section'][0]['var_template'] = $var_template;
	//var_dump($sections);
	//var_dump($conf['section']);
	//foreach ($conf['section'] as &$section)
	//{
	//	printf("DBX,%s,%s,%s\n", $section{'sheet'},
	//		$section{'var_template'},
	//		$section{'var_data'});
	//}
}

include_once('/usr/share/php/tbs/tbs_class.php');

// new instance of TBS
$TBS = new clsTinyButStrong;

if ($template_ext==='docx' || $template_ext==='xlsx')
{
	// load the OpenTBS plugin
	include_once('/usr/share/php/tbs/plugins/tbs_plugin_opentbs.php');

	// load OpenTBS plugin
	$TBS->Plugin(TBS_INSTALL, OPENTBS_PLUGIN);
}

// Load the template
$TBS->LoadTemplate($template);


//var_dump($Config);
//var_dump($project);
//var_dump($cables);

// Automatic subblock
// $TBS->MergeBlock('project', $project);

foreach ($conf['section'] as &$section)
{
	if ( isset($section['sheet']) )
	{
		$sheet = $section['sheet'];
		$var_data = $section['var_data'];
		$var_template = $section['var_template'];

		//printf("%s,%s,%s\n", $section{'sheet'},
		//	$section{'var_template'},
		//	$section{'var_data'});

// specific merges depending to the document
		if ($template_ext==='xlsx')
		{

	// merge cells (exending columns)
	// $TBS->MergeBlock('cell1,cell2', $data);
	
	// change the current sheet
	// $TBS->PlugIn(OPENTBS_SELECT_SHEET, 2);
	
	// merge data in Sheet 2
	// $TBS->MergeBlock('cell1,cell2', 'num', 3);
	// $TBS->MergeBlock('b2', $data);
	
	// Delete a sheet
	// $TBS->PlugIn(OPENTBS_DELETE_SHEETS, 'Delete me');
	
	// Display a sheet
	// $TBS->PlugIn(OPENTBS_DISPLAY_SHEETS, 'Display me');

	// Change the current sheet
	//$TBS->PlugIn(OPENTBS_SELECT_SHEET, 'Devices');
	//$TBS->MergeBlock('devices', $devices);

	//$TBS->PlugIn(OPENTBS_SELECT_SHEET, 'Version');
	//$TBS->MergeBlock('versions',$Versions);

			if ($sheet!=='default')
			{
				$TBS->PlugIn(OPENTBS_SELECT_SHEET, $sheet);
			}
		}
		elseif ($template_ext==='docx')
		{

	// change chart series
//	$ChartNameOrNum = 'chart1';
//	$SeriesNameOrNum = 2;
//	$NewValues = array( array('Category A','Category B','Category C','Category D'), array(3, 1.1, 4.0, 3.3) );
//	$NewLegend = "New series 2";
//	$TBS->PlugIn(OPENTBS_CHART, $ChartNameOrNum, $SeriesNameOrNum, $NewValues, $NewLegend);

	// delete comments
//	$TBS->PlugIn(OPENTBS_DELETE_COMMENTS);

		}
		else
		{
			// Contacts
			//$TBS->MergeBlock('contacts',$Contacts);
		}

		$data = $Config[$var_data];
		$TBS->MergeBlock($var_template, $data);
	}
}

// Define the name of the output file
$output_filename = $output;

if ($template_ext==='docx' || $template_ext==='xlsx')
{
	// Save as file
	$TBS->Show(OPENTBS_FILE+TBS_EXIT, $output_filename);
}
else
{
	if ( ! ($output_filename === "-") )
	{
		fclose(STDOUT);
		$STDOUT = fopen($output_filename, "wb");
	}
	$TBS->Show();
	if ( ! ($output_filename === "-") )
	{
		fclose(STDOUT);
	}
}

?>
