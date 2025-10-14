#!/usr/bin/env python3
"""
Enhanced Cloud Custodian Garbage Collection Script
Properly handles CloudWatch Events rules with targets and other AWS resources
"""

import argparse
import itertools
import json
import os
import re
import logging
import sys
import time
from typing import List, Dict, Any

from c7n.credentials import SessionFactory
from c7n.config import Config
from c7n.policy import load as policy_load, PolicyCollection
from c7n import mu

from c7n.resources.aws import AWS
from botocore.exceptions import ClientError


log = logging.getLogger('mugc-enhanced')


def load_policies(options, config):
    """Load policies from configuration files."""
    policies = PolicyCollection([], config)
    for f in options.config_files:
        policies += policy_load(config, f).filter(options.policy_filters)
    return policies


def cleanup_cloudwatch_events_rule(events_client, rule_name: str, dryrun: bool = False) -> bool:
    """
    Properly clean up a CloudWatch Events rule by first removing targets.
    
    Args:
        events_client: Boto3 CloudWatch Events client
        rule_name: Name of the rule to delete
        dryrun: If True, only log what would be done
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        # First, list all targets for the rule
        log.info(f"Checking targets for rule: {rule_name}")
        targets_response = events_client.list_targets_by_rule(Rule=rule_name)
        targets = targets_response.get('Targets', [])
        
        if targets:
            log.info(f"Found {len(targets)} targets for rule {rule_name}")
            if not dryrun:
                # Remove all targets
                target_ids = [target['Id'] for target in targets]
                log.info(f"Removing targets {target_ids} from rule {rule_name}")
                
                remove_response = events_client.remove_targets(
                    Rule=rule_name,
                    Ids=target_ids
                )
                
                if remove_response.get('FailedEntryCount', 0) > 0:
                    log.error(f"Failed to remove some targets from rule {rule_name}: {remove_response.get('FailedEntries', [])}")
                    return False
                
                log.info(f"Successfully removed targets from rule {rule_name}")
                
                # Wait a moment for the targets to be fully removed
                time.sleep(2)
            else:
                log.info(f"DRYRUN: Would remove {len(targets)} targets from rule {rule_name}")
        
        # Now delete the rule
        log.info(f"Deleting rule: {rule_name}")
        if not dryrun:
            events_client.delete_rule(Name=rule_name)
            log.info(f"Successfully deleted rule {rule_name}")
        else:
            log.info(f"DRYRUN: Would delete rule {rule_name}")
            
        return True
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'ResourceNotFoundException':
            log.info(f"Rule {rule_name} not found (already deleted)")
            return True
        else:
            log.error(f"Error handling rule {rule_name}: {e}")
            return False
    except Exception as e:
        log.error(f"Unexpected error handling rule {rule_name}: {e}")
        return False


def cleanup_config_rules(config_client, rule_name: str, dryrun: bool = False) -> bool:
    """
    Clean up AWS Config rules.
    
    Args:
        config_client: Boto3 Config client
        rule_name: Name of the config rule to delete
        dryrun: If True, only log what would be done
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        log.info(f"Deleting Config rule: {rule_name}")
        if not dryrun:
            config_client.delete_config_rule(ConfigRuleName=rule_name)
            log.info(f"Successfully deleted Config rule {rule_name}")
        else:
            log.info(f"DRYRUN: Would delete Config rule {rule_name}")
        return True
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'NoSuchConfigRuleException':
            log.info(f"Config rule {rule_name} not found (already deleted)")
            return True
        else:
            log.error(f"Error deleting Config rule {rule_name}: {e}")
            return False


def cleanup_lambda_function_resources(session_factory, function_name: str, dryrun: bool = False) -> bool:
    """
    Clean up resources associated with a Lambda function before removing the function.
    
    Args:
        session_factory: C7N session factory
        function_name: Name of the Lambda function
        dryrun: If True, only log what would be done
        
    Returns:
        bool: True if successful, False otherwise
    """
    session = session_factory()
    lambda_client = session.client('lambda')
    events_client = session.client('events')
    config_client = session.client('config')
    
    success = True
    
    try:
        # Get the function's policy to understand what resources are attached
        result = lambda_client.get_policy(FunctionName=function_name)
        
        if 'Policy' in result:
            policy = json.loads(result['Policy'])
            
            for statement in policy.get('Statement', []):
                principal = statement.get('Principal')
                if not isinstance(principal, dict):
                    continue
                
                # Handle CloudWatch Events
                if principal == {'Service': 'events.amazonaws.com'}:
                    log.info(f"Found CloudWatch Events integration for {function_name}")
                    
                    # Try to find and clean up the associated rule
                    # The rule name typically follows the pattern: custodian-{policy-name}
                    rule_pattern = function_name.replace('custodian-', '', 1)
                    potential_rule_names = [
                        f"custodian-{rule_pattern}",
                        f"custodian-{rule_pattern}-scheduled",
                        rule_pattern,
                        function_name
                    ]
                    
                    for rule_name in potential_rule_names:
                        try:
                            events_client.describe_rule(Name=rule_name)
                            log.info(f"Found CloudWatch Events rule: {rule_name}")
                            if not cleanup_cloudwatch_events_rule(events_client, rule_name, dryrun):
                                success = False
                        except ClientError as e:
                            if e.response['Error']['Code'] != 'ResourceNotFoundException':
                                log.debug(f"Rule {rule_name} not found, trying next pattern")
                
                # Handle AWS Config
                elif principal == {'Service': 'config.amazonaws.com'}:
                    log.info(f"Found AWS Config integration for {function_name}")
                    
                    # The config rule name typically matches the function name pattern
                    config_rule_pattern = function_name.replace('custodian-', '', 1)
                    potential_config_names = [
                        config_rule_pattern,
                        f"custodian-{config_rule_pattern}",
                        function_name
                    ]
                    
                    for config_rule_name in potential_config_names:
                        try:
                            config_client.describe_config_rules(ConfigRuleNames=[config_rule_name])
                            log.info(f"Found Config rule: {config_rule_name}")
                            if not cleanup_config_rules(config_client, config_rule_name, dryrun):
                                success = False
                        except ClientError as e:
                            if e.response['Error']['Code'] != 'NoSuchConfigRuleException':
                                log.debug(f"Config rule {config_rule_name} not found, trying next pattern")
    
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            log.info(f"Lambda function {function_name} policy not found (function may already be deleted)")
        else:
            log.warning(f"Error getting policy for function {function_name}: {e}")
            success = False
    
    return success


def region_gc(options, region, policy_config, policies):
    """Enhanced garbage collection for a specific region."""
    log.debug("Region:%s Starting enhanced garbage collection", region)
    
    session_factory = SessionFactory(
        region=region,
        assume_role=policy_config.assume_role,
        profile=policy_config.profile,
        external_id=policy_config.external_id)

    manager = mu.LambdaManager(session_factory)
    funcs = list(manager.list_functions(options.prefix))
    
    remove = []
    pattern = re.compile(options.policy_regex)
    
    for f in funcs:
        if not pattern.match(f['FunctionName']):
            continue
        match = False
        for p in policies:
            if f['FunctionName'].endswith(p.name):
                if 'region' not in p.data or p.data['region'] == region:
                    match = True
        
        if options.present:
            if match:
                remove.append(f)
        elif not match:
            remove.append(f)

    log.info(f"Region:{region} Found {len(remove)} functions to remove")
    
    for func_info in remove:
        function_name = func_info['FunctionName']
        log.info(f"Region:{region} Processing function: {function_name}")
        
        # First, clean up associated resources (CloudWatch Events, Config rules, etc.)
        if not cleanup_lambda_function_resources(session_factory, function_name, options.dryrun):
            log.warning(f"Region:{region} Some resources for {function_name} could not be cleaned up")
        
        # Create Lambda function object for removal
        events = []
        
        # Note: We've already cleaned up the actual resources above,
        # but we still need to provide the events list for the LambdaFunction object
        try:
            session = session_factory()
            lambda_client = session.client('lambda')
            result = lambda_client.get_policy(FunctionName=function_name)
            
            if 'Policy' in result:
                policy = json.loads(result['Policy'])
                for statement in policy.get('Statement', []):
                    principal = statement.get('Principal')
                    if not isinstance(principal, dict):
                        continue
                    if principal == {'Service': 'events.amazonaws.com'}:
                        events.append(mu.CloudWatchEventSource({}, session_factory))
                    elif principal == {'Service': 'config.amazonaws.com'}:
                        events.append(mu.ConfigRule({}, session_factory))
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                log.info(f"Region:{region} Function {function_name} policy not found")
            else:
                log.warning(f"Region:{region} Error getting policy for {function_name}: {e}")

        # Create LambdaFunction object and remove it
        lambda_func = mu.LambdaFunction({
            'name': function_name,
            'role': func_info['Role'],
            'handler': func_info['Handler'],
            'timeout': func_info['Timeout'],
            'memory_size': func_info['MemorySize'],
            'description': func_info['Description'],
            'runtime': func_info['Runtime'],
            'events': events
        }, None)

        log.info(f"Region:{region} Removing Lambda function: {function_name}")
        if options.dryrun:
            log.info("DRYRUN: Skipping Lambda function removal")
            continue
        
        try:
            manager.remove(lambda_func)
            log.info(f"Region:{region} Successfully removed function: {function_name}")
        except Exception as e:
            log.error(f"Region:{region} Error removing function {function_name}: {e}")


def resources_gc_prefix(options, policy_config, policy_collection):
    """Enhanced garbage collection for Cloud Custodian resources."""
    # Classify policies by region
    policy_regions = {}
    for p in policy_collection:
        if p.execution_mode == 'poll':
            continue
        policy_regions.setdefault(p.options.region, []).append(p)

    regions = get_gc_regions(options.regions, policy_config)
    for r in regions:
        region_gc(options, r, policy_config, policy_regions.get(r, []))


def get_gc_regions(regions, policy_config):
    """Get list of regions for garbage collection."""
    if 'all' in regions:
        session_factory = SessionFactory(
            region='us-east-1',
            assume_role=policy_config.assume_role,
            profile=policy_config.profile,
            external_id=policy_config.external_id)

        client = session_factory().client('ec2')
        return [region['RegionName'] for region in client.describe_regions()['Regions']]
    return regions


def setup_parser():
    """Set up command line argument parser."""
    parser = argparse.ArgumentParser(
        description="Enhanced Cloud Custodian Garbage Collection - properly handles CloudWatch Events rules with targets"
    )
    parser.add_argument("configs", nargs='*', help="Policy configuration file(s)")
    parser.add_argument(
        '-c', '--config', dest="config_files", nargs="*", action='append',
        help="Policy configuration files(s)", default=[])
    parser.add_argument(
        "--present", action="store_true", default=False,
        help='Target policies present in config files for removal instead of skipping them.')
    parser.add_argument(
        '-r', '--region', action='append', dest='regions', metavar='REGION',
        help="AWS Region to target. Can be used multiple times, also supports `all`")
    parser.add_argument('--dryrun', action="store_true", default=False,
                       help="Show what would be deleted without actually deleting")
    parser.add_argument(
        "--profile", default=os.environ.get('AWS_PROFILE'),
        help="AWS Account Config File Profile to utilize")
    parser.add_argument(
        "--prefix", default="custodian-",
        help="The Lambda name prefix to use for clean-up")
    parser.add_argument(
        "--policy-regex",
        help="The policy must match the regex")
    parser.add_argument("-p", "--policies", default=[], dest='policy_filters',
                        action='append', help="Only use named/matched policies")
    parser.add_argument(
        "--assume", default=None, dest="assume_role",
        help="Role to assume")
    parser.add_argument(
        "-v", dest="verbose", action="store_true", default=False,
        help='toggle verbose logging')
    return parser


def main():
    """Main entry point."""
    parser = setup_parser()
    options = parser.parse_args()

    log_level = logging.INFO
    if options.verbose:
        log_level = logging.DEBUG
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s: %(name)s:%(levelname)s %(message)s")
    logging.getLogger('botocore').setLevel(logging.ERROR)
    logging.getLogger('urllib3').setLevel(logging.ERROR)
    logging.getLogger('c7n.cache').setLevel(logging.WARNING)

    if not options.policy_regex:
        options.policy_regex = f"^{options.prefix}.*"

    if not options.regions:
        options.regions = [os.environ.get('AWS_DEFAULT_REGION', 'us-east-1')]

    files = []
    files.extend(itertools.chain(*options.config_files))
    files.extend(options.configs)
    options.config_files = files

    if not files:
        parser.print_help()
        sys.exit(1)

    policy_config = Config.empty(
        regions=options.regions,
        profile=options.profile,
        assume_role=options.assume_role)

    # Use cloud provider to initialize policies to get region expansion
    policies = AWS().initialize_policies(
        PolicyCollection([
            p for p in load_policies(options, policy_config)
            if p.provider_name == 'aws'
        ], policy_config),
        policy_config)

    log.info("Starting enhanced garbage collection...")
    if options.dryrun:
        log.info("DRYRUN MODE: No resources will be actually deleted")
    
    resources_gc_prefix(options, policy_config, policies)
    log.info("Enhanced garbage collection completed")


if __name__ == '__main__':
    main()