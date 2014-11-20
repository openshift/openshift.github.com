<?php
    //API Key - see http://admin.mailchimp.com/account/api
    $apikey = 'f4cc5558d88651c208d129bec6f55e43-us3';  //YOUR MAILCHIMP APIKEY
    
    // A List Id to run examples against. use lists() to view all
    // Also, login to MC account, go to List, then List Tools, and look for the List ID entry
    $listId = '7bf609a7a9'; //YOUR LIST ID
    
    // A Campaign Id to run examples against. use campaigns() to view all
    $campaignId = 'YOUR MAILCHIMP CAMPAIGN ID - see campaigns() method';

    //some email addresses used in the examples:
    $my_email = 'jdrendon@imaginacionweb.net';
    $boss_man_email = 'jmartinez@imaginacionweb.net';

    //just used in xml-rpc examples
    $apiUrl = 'http://api.mailchimp.com/1.3/';
    
?>
