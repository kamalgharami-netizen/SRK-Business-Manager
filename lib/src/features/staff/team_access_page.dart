import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamAccessPage extends StatefulWidget {
  const TeamAccessPage({super.key,required this.businessId});
  final String businessId;
  @override
  State<TeamAccessPage> createState()=>_TeamAccessPageState();
}
class _TeamAccessPageState extends State<TeamAccessPage>{
  bool _loading=true,_busy=false;
  String? _error;
  String _myRole='';
  List<Map<String,dynamic>> _members=[];
  SupabaseClient get _client=>Supabase.instance.client;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async{
    setState(()=>_loading=true);
    try{
      final rows=await _client.rpc('list_business_members',params:{'target_business_id':widget.businessId});
      final list=List<Map<String,dynamic>>.from((rows as List).map((e)=>Map<String,dynamic>.from(e as Map)));
      final me=_client.auth.currentUser?.id;
      if(!mounted)return;
      setState((){
        _members=list;
        _myRole=list.firstWhere((e)=>e['user_id']==me,orElse:()=>{})['role'] as String? ?? '';
        _error=null;_loading=false;
      });
    }catch(e){if(mounted)setState(()=>{_error=e.toString(),_loading=false});}
  }
  Future<void> _add() async{
    final email=TextEditingController();String role='viewer';final key=GlobalKey<FormState>();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(
      title:const Text('Add existing cloud user'),
      content:Form(key:key,child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Registered email'),validator:(v)=>v==null||!v.contains('@')?'Enter a valid email':null),
        DropdownButtonFormField<String>(value:role,decoration:const InputDecoration(labelText:'Role'),items:const [
          DropdownMenuItem(value:'admin',child:Text('Admin')),DropdownMenuItem(value:'accountant',child:Text('Accountant')),DropdownMenuItem(value:'sales',child:Text('Sales')),DropdownMenuItem(value:'viewer',child:Text('Viewer')),
        ],onChanged:(v)=>refresh(()=>role=v??'viewer')),
        const Text('The person must already have registered. This does not send an invitation email.',style:TextStyle(fontSize:12)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,key.currentState!.validate()),child:const Text('Add'))],
    )));
    if(ok!=true){email.dispose();return;}
    setState(()=>_busy=true);
    try{
      await _client.rpc('add_business_member',params:{'target_business_id':widget.businessId,'member_email':email.text.trim(),'member_role':role});
      email.dispose();await _load();
    }catch(e){email.dispose();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not add user: $e')));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _change(Map<String,dynamic> m,String role) async{
    setState(()=>_busy=true);
    try{await _client.rpc('update_business_member_role',params:{'target_business_id':widget.businessId,'target_user_id':m['user_id'],'new_role':role});await _load();}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Role update failed: $e')));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _remove(Map<String,dynamic> m) async{
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Remove user?'),content:Text('Remove '+(m['email'] as String? ?? 'this user')+' from this business?'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Remove'))],
    ));
    if(ok!=true)return;
    setState(()=>_busy=true);
    try{await _client.rpc('remove_business_member',params:{'target_business_id':widget.businessId,'target_user_id':m['user_id']});await _load();}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Remove failed: $e')));}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Team & Access Permissions')),
    floatingActionButton:(_myRole=='owner'||_myRole=='admin')?FloatingActionButton.extended(
      onPressed:_busy||_members.length>=10?null:_add,icon:const Icon(Icons.person_add),label:const Text('Add user')):null,
    body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text('Could not load team: '+_error!),OutlinedButton(onPressed:_load,child:const Text('Retry')),
    ])):Column(children:[
      MaterialBanner(content:Text('Business accounts: '+_members.length.toString()+'/10 • Available seats: '+(10-_members.length).toString()),actions:const [SizedBox.shrink()]),
      if(_busy)const LinearProgressIndicator(),
      Expanded(child:ListView.separated(padding:const EdgeInsets.all(16),itemCount:_members.length,separatorBuilder:(_,i)=>const Divider(),itemBuilder:(ctx,i){
        final m=_members[i];final role=m['role'] as String? ?? 'viewer';final owner=role=='owner';
        final manage=_myRole=='owner'||(_myRole=='admin'&&!owner&&role!='admin');
        return ListTile(
          leading:CircleAvatar(child:Icon(owner?Icons.verified_user:Icons.person)),
          title:Text((m['email'] as String?)?.isNotEmpty==true?m['email'] as String:m['user_id'] as String),
          subtitle:Text(role.toUpperCase()),
          trailing:manage?Wrap(spacing:4,children:[
            DropdownButton<String>(value:owner?null:role,hint:const Text('Role'),items:[
              if(_myRole=='owner')const DropdownMenuItem(value:'admin',child:Text('Admin')),
              const DropdownMenuItem(value:'accountant',child:Text('Accountant')),const DropdownMenuItem(value:'sales',child:Text('Sales')),const DropdownMenuItem(value:'viewer',child:Text('Viewer')),
            ],onChanged:_busy||owner?null:(v){if(v!=null&&v!=role)_change(m,v);}),
            IconButton(onPressed:_busy||owner?null:()=>_remove(m),icon:const Icon(Icons.person_remove),tooltip:'Remove user'),
          ]):null,
        );
      })),
    ]),
  );
}
